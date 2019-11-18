#!/usr/bin/env python3

ucs_list = [
]

for host in ucs_list:
    diassemble_host_start = host.split(".")[0]
    diassemble_host_end = host.split(".")[1:]
    #print("--------------------------------------------------")
    first_part_fiA = diassemble_host_start + "-a"
    first_part_fiB = diassemble_host_start + "-b"
    for i in host.split(".")[1:]:
        first_part_fiA += "." + i
        first_part_fiB += "." + i
    print(first_part_fiA)
    print(first_part_fiB)
