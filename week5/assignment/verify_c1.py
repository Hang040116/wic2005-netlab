#!/usr/bin/env python3
"""Measure the legacy pipeline on two finite, forward-only paths."""
import argparse
from collections import Counter
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from mininet.log import setLogLevel
from mininet.net import Mininet
from scapy.all import rdpcap

LAB = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LAB))
from topo import BMv2Switch, SWITCH_BUILD, THRIFT_PORT, compile_program


def measure(length, address_octet):
    source = f"10.{address_octet}.0.1"
    destination = f"10.{address_octet}.0.3"
    net = Mininet(controller=None, autoSetMacs=True, build=False)
    sender = net.addHost("h1", ip=f"{source}/24")
    receiver = net.addHost("h3", ip=f"{destination}/24")
    stages = []
    upstream = sender
    for index in range(1, length + 1):
        name = f"p{index}"
        THRIFT_PORT[name] = 9100 + index
        SWITCH_BUILD[name] = "build/tunnel_v1.json"
        switch = net.addSwitch(name, cls=BMv2Switch)
        net.addLink(upstream, switch)
        upstream = switch
        stages.append(name)
    net.addLink(upstream, receiver)
    capture = None
    try:
        net.build()
        for host in (sender, receiver):
            host.cmd("sysctl -qw net.ipv6.conf.all.disable_ipv6=1 "
                     "net.ipv6.conf.default.disable_ipv6=1")
        net.start()
        for name in stages:
            result = subprocess.run(
                ["simple_switch_CLI", "--thrift-port", str(THRIFT_PORT[name])],
                input="table_add MyIngress.myTunnel_exact MyIngress.myTunnel_forward 3 => 2\n",
                text=True, capture_output=True, check=True,
            )
            if "Entry has been added" not in result.stdout:
                raise RuntimeError(f"{name}: {result.stdout} {result.stderr}")

        capture = receiver.popen(
            ["tcpdump", "-U", "-c", "1", "-ni", "h3-eth0", "-w", "received.pcap",
             "ether proto 0x1212"],
            stderr=subprocess.PIPE, text=True,
        )
        if "listening on" not in capture.stderr.readline():
            raise RuntimeError("The receiver capture failed to start.")

        send_one = f"""
import struct
from scapy.all import Ether, IP, UDP, raw, sendp
inner = IP(src={source!r}, dst={destination!r}, ttl=64) / UDP(sport=4321, dport=4321) / b"legacy-baseline"
frame = Ether(src="00:00:00:00:00:01", dst="00:00:00:00:00:02", type=0x1212)
packet = frame / (struct.pack("!HH", 0x0800, 3) + raw(inner))
with open("sent.bin", "wb") as output:
    output.write(raw(packet))
sendp(packet, iface="h1-eth0", count=1, verbose=False)
"""
        sent = sender.popen(["python3", "-c", send_one])
        if sent.wait(timeout=15):
            raise RuntimeError("The sender failed.")
        if capture.wait(timeout=10):
            raise RuntimeError("The receiver capture failed.")

        packets = rdpcap("received.pcap")
        expected = Path("sent.bin").read_bytes()
        if len(packets) != 1 or bytes(packets[0]) != expected:
            raise AssertionError("Expected a single byte-identical legacy frame at the sink.")

        roles = Counter()
        print(f"Sent one legacy tunnel frame from {source} to {destination}, exit ID 3.")
        for index, name in enumerate(stages):
            log = Path("logs", f"{name}.txt").read_text()
            count = log.count("Processing packet received")
            if count != 1:
                raise AssertionError(f"{name}: expected one logged arrival, observed {count}.")
            role = "s1" if index % 2 == 0 else "s2"
            roles[role] += count
            print(f"{name} ({role} role): {count} logged arrival")
        print(f"Measured totals: {roles['s1']} s1-role arrivals, {roles['s2']} s2-role arrivals.")
        print(f"Sink captured exactly one byte-identical frame ({len(expected)} bytes).")
    finally:
        if capture is not None and capture.poll() is None:
            capture.terminate()
            capture.wait(timeout=5)
        net.stop()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--id", required=True, help="last four digits of the student ID")
    args = parser.parse_args()
    if len(args.id) != 4 or not args.id.isascii() or not args.id.isdigit():
        parser.error("--id must be four ASCII digits")
    setLogLevel("info")
    print("Bounded BMv2 measurement: independent forward-only paths; no live cycle.")
    initial_dir = Path.cwd()
    for length in (4, 12):
        print(f"\n=== {length} forwarding stages ===", flush=True)
        with tempfile.TemporaryDirectory(prefix="c1-bmv2-") as directory:
            os.chdir(directory)
            try:
                compile_program(str(LAB / "tunnel_v1.p4"), "build/tunnel_v1.json")
                measure(length, int(args.id[-2:]))
            finally:
                os.chdir(initial_dir)


if __name__ == "__main__":
    main()
