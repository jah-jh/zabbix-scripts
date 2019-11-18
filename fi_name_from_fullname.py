#!/usr/bin/env python3

ucs_list = [
    'ucs1.compute.otp1.edc.strln.net', 'ucs1.compute.mum1.edc.strln.net',
    'ucs1.compute.dxb1.edc.strln.net', 'ucs1.compute.dub1.edc.strln.net',
    'ucs1.compute.cph1.edc.strln.net', 'ucs1.compute.cdg1.edc.strln.net',
    'ucs1.compute.mel1.edc.strln.net', 'ucs1.compute.prg1.edc.strln.net',
    'ucs1.compute.mil1.edc.strln.net', 'ucs1.compute.den1.edc.strln.net',
    'ucs1.compute.wrw1.edc.strln.net', 'ucs1.compute.lon1.edc.strln.net',
    'ucs2.compute.lon1.edc.strln.net', 'ucs1.compute.atl1.edc.strln.net',
    'ucs1.compute.ash1.edc.strln.net', 'ucs1.compute.dfw1.edc.strln.net',
    'ucs1.compute.pao1.edc.strln.net', 'ucs1.compute.lax1.edc.strln.net',
    'ucs1.compute.mia1.edc.strln.net', 'ucs1.compute.nyc1.edc.strln.net',
    'ucs1.compute.ams1.edc.strln.net', 'ucs1.compute.syd1.edc.strln.net',
    'ucs1.compute.fra1.edc.strln.net', 'ucs1.compute.sin1.edc.strln.net',
    'ucs1.compute.nrt1.edc.strln.net', 'ucs1.compute.yyz1.edc.strln.net'
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
