import os
import subprocess
import copy
import sys
import csv

def powerset(L):
    if L == []:
        return [[]]
    else:
        restPowerset = powerset(L[1:])
        return [[L[0]] + s for s in restPowerset] + restPowerset

def parse_output_for_setting(base_dir, filename, formatted_output_dir):
    with open(os.path.join(base_dir, filename)) as f:
        file_string = f.read()
    # with open(bench0file) as f:
    #     file_string = f.read()
    # with open(bench1file) as f:
    #     file_string += f.read()
    by_test_file = file_string.split("Timing file ")[1:]
    test_filenames = []
    times_per_file = []
    for test_file_string in by_test_file:
        assert(test_file_string[:10] == "../bench0/" or
               test_file_string[:10] == "../bench1/")
        test_filename_end = test_file_string.find(".l4")
        test_filename = test_file_string[10:test_filename_end]
        first_time_indicator = "-O0: "
        first_time_start = (test_file_string.find(first_time_indicator)
                            + len(first_time_indicator))
        recordedTime = ""
        i = first_time_start
        while test_file_string[i].isdigit():
            recordedTime += test_file_string[i]
            i+=1
        recordedTime = int(recordedTime)
        test_filenames.append(test_filename)
        times_per_file.append(recordedTime)
    if len(times_per_file) != 13:
        print filename, len(times_per_file)
    noExtension = filename[:filename.find('.')]
    
    newFileName = os.path.join(base_dir,formatted_output_dir, noExtension +'.csv')
    newFileName = newFileName.replace('RawOutput', 'FormattedOutput')
    
    with open(newFileName, 'w') as f:
        writer = csv.writer(f)
        for i in xrange(len(test_filenames)):
            writer.writerow([test_filenames[i], times_per_file[i]])

def parse_all(base_dir, formatted_output_dir):
    for filename in os.listdir(base_dir):
        if filename.endswith(".txt") and filename.startswith('bench0'):
            parse_output_for_setting(base_dir, filename, formatted_output_dir)
        
def time_all(opts):
    opts_list = opts.items()
    opt_settings = [s for s in powerset(opts_list) if 0 < len(s) and len(s) < 3]
    print len(opt_settings)
    formatted_settings = [("-".join([name for (name, flag) in setting]),
                           ",".join([flag for (name, flag) in setting]))
                          for setting in opt_settings]
    other_settings = [("O0", "--noRegAlloc"), ("O1", "-r 0"),
                      ("O2", "--killDeadCode --doConstOpts --doInlining" +
                      " --onlyPushOnce -r 5")]
    formatted_settings += other_settings
    for (name, flags) in formatted_settings:
        output_filename0 = "timingOutput/bench0RawOutput_" + name + ".txt"
        print flags
        # subprocess.call("../grader/timecompiler bench0 --limit-run=30 -a " + flags
        #                 + " >& " + output_filename0, shell=True)
        output_filename1 = "timingOutput/bench1RawOutput_" + name + ".txt"
        subprocess.call("../grader/timecompiler bench1 --limit-run=30 -a " + flags
                        + " >& " + output_filename1, shell=True)

def main():
    # maps the name to the command line flag
    opts = { "DeadCode":"--killDeadCode",
             "ConstOpts":"--doConstOpts",
             "Inlining":"--doInlining",
             "OnlyPushOnce":"--onlyPushOnce",
             "Alloc5More":"-r 5",
             "unsafe":"--unsafeForExperiments"
             }
    #time_all(opts)
    parse_all("timeData", "formattedOutput")
             
if __name__ == "__main__":
    main()
