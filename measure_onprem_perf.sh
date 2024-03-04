#!/bin/bash

sudo apt update -y
sudo apt install -y sysbench iperf3

# Function to measure CPU performance
measure_cpu_performance() {
    echo "Measuring CPU performance..."
    sysbench cpu --cpu-max-prime=20000 --threads=4 run
}

# Function to measure network performance
measure_network_performance() {
    echo "Measuring network performance..."
    iperf3 -s & # Start iperf3 server in the background
    sleep 2 # Give some time for the server to start
    iperf3 -c localhost # Run iperf3 client locally
    pkill iperf3 # Stop iperf3 server
}

# Function to measure storage performance
measure_storage_performance() {
    echo "Measuring storage performance..."
    time dd if=/dev/zero of=/var/lib/test.png bs=8192 count=10240 oflag=direct
}

# Main function
main() {
    measure_cpu_performance
    measure_network_performance
    measure_storage_performance
}

# Execute main function
main
