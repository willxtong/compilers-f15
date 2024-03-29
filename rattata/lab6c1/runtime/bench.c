/*******************************************************************
 *
 * bench.c - Benchmark run for 15-411 Compiler Design Lab 6 optimization
 *
 ********************************************************************/

#define _GNU_SOURCE
#include <sched.h>
#include <stdio.h>
#include <signal.h>
#include <stdlib.h>
#include <getopt.h>
#include <time.h>


#define MAXITERS 5000 	       /* Max number of iterations of benchmarks */
#define KBEST 200
#define EPSILON 0.005          /* KBEST samples should be within EPSILON */

/* extern int _c0_main(); */    /* unused here */
extern void* _c0_init(int param);
extern void _c0_prepare(void* data, int param);
extern void _c0_run(void* data, int param);
extern int _c0_checksum(void* data, int param);

/*********************************/
/* Cycle counting infrastructure */
/*********************************/

/* Initialize the cycle counter */
static unsigned cyc_hi = 0;
static unsigned cyc_lo = 0;

/* Set *hi and *lo to the high and low order bits  of the cycle counter.
   Implementation requires assembly code to use the rdtsc instruction. */
void access_counter(unsigned *hi, unsigned *lo)
{
	asm __volatile__ ("xorl %%eax, %%eax; cpuid"
	        ::: "%rax", "%rbx", "%rcx", "%rdx");
	asm __volatile__ ("rdtsc"   /* Read cycle counter */
	        : "=a" (*lo), "=d" (*hi));
}

/* Record the current value of the cycle counter. */
void start_counter()
{
	access_counter(&cyc_hi, &cyc_lo);
}

unsigned long to64(unsigned hi32, unsigned lo32) {
	return (((unsigned long)hi32)<<32) + (unsigned long)lo32;
}

/* Return the number of cycles since the last call to start_counter. */
unsigned long get_counter()
{
	unsigned ncyc_hi, ncyc_lo;
	unsigned long now, before;

	/* Get cycle counter */
	access_counter(&ncyc_hi, &ncyc_lo);
	now = to64(ncyc_hi, ncyc_lo);
	before = to64(cyc_hi, cyc_lo);
	return (now - before);
}

/*******************************/
/* Benchmarking infrastructure */
/*******************************/

/* Other globals */
static int debug_level = 0;

static unsigned long values[KBEST];
static int samplecount = 0;

static int add_sample(unsigned long val) {
  int pos = 0;
  if (samplecount < KBEST) {
    pos = samplecount;
    values[pos] = val;
  } else if (val < values[KBEST-1]) {
    pos = KBEST-1;
    values[pos] = val;
  }
  samplecount++;
  /* Insertion sort */
  while (pos > 0 && values[pos-1] > values[pos]) {
    unsigned long temp = values[pos-1];
    values[pos-1] = values[pos];
    values[pos] = temp;
    pos--;
  }

  return (samplecount >= KBEST
	  && (1.0+EPSILON)*(double)values[0] >= (double)values[KBEST-1]);
}

/* Function prototypes */
void usage(char *progname);
void init_timeout(int timeout);
unsigned long time_run();

/*
 * Main routine
 */
int main(int argc, char *argv[]) {
  char c;
  int i, j;
  void* data;
  int param;
  unsigned long cycles;
  /* removing scheduling affinity, -fp 2 Nov 2013 */
  /*
    cpu_set_t s;
  */
  /* Initialization */
  
  debug_level = 0;
  param = 1000;
  int checksums = 0;            /* do not write checksums by default */
  int verify = 0;               /* do not verify, by default */
  int checksum = 0;

  /* parse command line args */
  while ((c = getopt(argc, argv, "hkd:n:x:")) != -1) {
    switch (c) {
    case 'd': /* debug level */
      debug_level = atoi(optarg);
      break;

    case 'k': /* checksums */
      checksums = 1;
      break;

    case 'h': /* print help message */
      usage(argv[0]);
      break;

    case 'n': /* parameter value */
      param = atoi(optarg);
      break;

    case 'x': /* checksum */
      verify = 1;
      checksum = atoi(optarg);
      break;

    default: /* unrecognized argument */
      usage(argv[0]);
    }
  }

#ifdef __linux__
  cpu_set_t s;
  CPU_ZERO(&s);
  CPU_SET(0, &s);

  if (sched_setaffinity(0, sizeof(s), &s) < 0) {
    perror("sched_setaffinity");
    exit(-1);
  }
#endif

  /* Initialize and touch the input data */
  samplecount = 0;

  /* One run to warm up cache */
  data = _c0_init(param);
  _c0_prepare(data, param);
  time_run(data, param);
  /* Timing runs */

  if (checksums) {
    /* compute and print checksum */
    printf("%d\n", _c0_checksum(data, param));
    exit(0);
  }

  if (verify != 0) {
    int chk = _c0_checksum(data, param);
    if (chk != checksum) {
      fprintf(stderr, "Checksum %d != %d\n", chk, checksum);
      exit(1);
    }
  }

  for (i = 0; i < MAXITERS; i++) {
    _c0_prepare(data, param);
    cycles = time_run(data, param);
    if (add_sample(cycles)) {
      i++; break;
    }
  }

  cycles = 0;
  for (j = 0; j < KBEST; j++) {
    cycles += values[j];
  }
  cycles /= KBEST;

  // cycles = values[0];

  /* Print best score */
  if (debug_level >= 1) fprintf(stderr, "Iterations: %d\n", i);
  if (debug_level >= 1) fprintf(stderr, "Best cycles: %lu\n", values[0]);
  if (debug_level >= 1) fprintf(stderr, "%d-Best cycles: %lu\n", KBEST, cycles);
  printf("%lu\n", cycles);
  exit(0);
}

/*
 * time_run - Time a benchmark
 */
unsigned long time_run(void* data, int param) {
  unsigned long cycles;

  /* Time the function */
  /* no input, so no need to rewind */
  /* rewind(stdin); */
  start_counter();
  _c0_run(data, param);
  cycles = get_counter();
  if (debug_level >= 2) fprintf(stderr, "%lu cycles\n", cycles);
  return cycles;
}

/*
 * usage - print a usage message
 */
void usage(char *progname) {
	fprintf(stderr, "usage: %s [-hg]\n", progname);
	fprintf(stderr, "  -h        Print this message\n");
        fprintf(stderr, "  -k        Create checksums files\n");
        fprintf(stderr, "  -x <N>    Verify checksum = <N>\n");
	fprintf(stderr, "  -d <D>    Set debug level (default = 0)\n");
        fprintf(stderr, "  -n <N>    Set <N> as benchmark parameter (default = 1000)\n");
	exit(0);
}
