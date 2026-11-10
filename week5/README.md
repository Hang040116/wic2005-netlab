# Week 5: Programmable Data Planes (P4)

Two BMv2 switches run a P4 program that forwards plain IPv4 and tunnel traffic. The tunnel header carries an eight-bit hop budget. Each upgraded switch consumes one unit before forwarding and drops packets that arrive with zero remaining.

From this directory, start the network using the course lab image:

```sh
docker run --rm -it --privileged --network none --platform linux/amd64 \
  -v "${PWD}:/lab" -w /lab ghcr.io/firdaussahran/p4-lab:1.0 \
  python3 topo.py --id NNNN
```

Replace `NNNN` with your student ID suffix. The topology script compiles the P4 program, loads the forwarding tables and opens the Mininet CLI. Type `exit` to stop it. To run the old program on s2, append `--s2-program tunnel_v1.p4`.

The [assignment report](assignment/REPORT.md) explains the design, its boundary cases and the mixed rollout. The [evidence directory](assignment/evidence/) contains the test transcripts and the offline model of the original forwarding cycle. The [course lab instructions](https://firdaussahran.github.io/wic2005/weeks/week-05/#assignment--put-a-limit-on-the-tunnel) describe the starter and assignment.
