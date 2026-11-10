# Week 5 assignment — Put a limit on the tunnel

Student ID (last four digits): **3186**. The lab uses `10.86.0.0/24`.

## 1. Analysis: the loop

A tunnel packet for exit 3 is forwarded by its tunnel ID. If s1 and s2 both point that exit to each other, the next-hop sequence repeats s1 → s2 → s1. The original ingress has no hop field to end the sequence.

I measured the original P4 program in BMv2 using two independent forward-only paths. Each path expands the alternating switch roles into a fixed number of stages, all running the same `tunnel_v1.p4`. The [BMv2 transcript](evidence/loop-before.txt) shows one logged arrival per stage: two per role on the four-stage path and six per role on the twelve-stage path. In both runs, the sink captured one 61-byte frame identical to the input. Thus the legacy pipeline forwarded the packet at every tested stage without changing its bytes. These are stage counts from two finite runs, rather than time samples from a live two-switch loop. The [measurement script](verify_c1.py) reproduces both runs.

The plain IPv4 path has a separate issue. In the baseline, `ipv4_forward` selects the egress port and subtracts one from an unsigned eight-bit TTL. There is no guard to discard a packet at TTL 1 or 0. It can forward with TTL 0, then wrap from 0 to 255 on the next pass. The checksum is recomputed, so the TTL change itself does not invalidate the packet. This patch leaves the plain IPv4 path as supplied.

## 2. Design: the hop limit

The tunnel uses EtherType `0x1212` and carries the inner protocol and exit ID as two 16-bit fields. I append an unsigned eight-bit `hops_left` field after them. This keeps the lookup key at its original offset, adds one byte to the wire format, and provides values from 0 to 255. The inner IPv4 header moves by one byte, which matters during an upgrade.

The sender defaults to eight switch forwards. The longest normal lab path uses two, leaving six forwards of headroom, while an accidental cycle remains bounded. `--hops` overrides the default and accepts zero so the ingress drop can be tested directly.

A switch receiving zero drops the packet before lookup. With a positive budget, ingress decrements it once and applies the tunnel table. An egress packet may carry zero if this switch consumed its final allowed forward. For instance, two switches can deliver a packet starting at two with zero left at the host. The inner IPv4 TTL is separate and stays unchanged on the tunnel path.

## 3. Implementation

The P4 parser extracts the new field as part of the tunnel header and the deparser emits the updated header. The table still looks up the exit ID and retains its default drop for unknown exits. The check comes before subtraction, so zero cannot wrap to 255. The sender and receiver use the same field order and sizes as P4. The receiver reports the remaining budget alongside the tunnel ID and inner IPv4 TTL.

## 4. Evidence: it works

Both programs compiled with the course's P4 compiler. With the new program on both switches, [delivery.txt](evidence/delivery.txt) shows:

| Test from h1 | Observation |
| --- | --- |
| Exit 2, inner IP `10.86.0.3`, default budget 8 | h2 received `exit-2-default` with 6 hops left and inner TTL 64. |
| Exit 3, budget 2 | h3 received `exit-3-last-hop` with 0 hops left and inner TTL 64. |
| Exit 3, budgets 0 and 1 | Neither test message appeared in the receiver logs. |
| Plain IPv4 ping to h3 | Two replies, zero loss, TTL 62. |

[loop-after.txt](evidence/loop-after.txt) shows a fresh network with both switches upgraded. With budget 4, the packet was forwarded by s1, s2, s1, and s2, then arrived at s1 with zero and was dropped. Relative to the initial counts of 8 and 7, s1 processed three additional arrivals and s2 processed two. The counts stayed at 11 and 9 in the later sample. That is four forwards and one final arrival that dropped.

## 5. Evaluation

### Mixed rollout prediction (written before running the experiment)

s1 will parse the new five-byte tunnel header, decrement the budget, and preserve the exit ID. s2 will consume only the first four bytes. It should still hit the intended exit because that key is unchanged, but it will parse the remaining hop byte as the first byte of IPv4. In a send with a starting budget of four, the old parser will see `03 45` where the IPv4 header should begin with `45 00`. The old checksum computation may modify bytes at the wrong offset, so even a forwarded frame may be unreadable as UDP at the receiver. For a path that revisits s1, the old s2 does not decrement the budget, so I expect the frame to use one unit per visit to s1 and eventually stop. I do not expect this guarantee on a path made entirely of old switches.

### Mixed rollout observation

In [mixed.txt](evidence/mixed.txt), both Ethernet frames arrived at h2. Only the first decoded as UDP in `receive.py`. The s2 trace shows it entered `parse_ipv4` and recomputed a checksum for both frames.

- Starting at 4 left `03` after s1. In the old parser's 20-byte window, that `03` replaced the actual last IPv4 byte, which was also `03` for destination `10.86.0.3`. This amounts to a one-byte circular rotation of the valid IPv4 header. The Internet checksum still balances under that rotation, so rewriting the checksum in the shifted window happened to leave the real bytes unchanged. The capture retains `40 11 66 11` for TTL, protocol, and checksum. h2 printed the UDP payload with three hops left.
- Starting at 5 left `04` after s1. The otherwise comparable frame no longer balances in that shifted window. The legacy checksum write changed `40 11 66 11` to `40 10 66 11` at the receiver. The `11` (UDP) to `10` change explains why h2 saw the Ethernet frame but did not log a UDP message. The old parser still selected the same exit because the exit ID's position did not change.

The mixed cycle added five arrivals at s1 and four at s2. The counts moved from 2/2 to 7/6 and stayed there. Each of the first four arrivals at s1 consumed one unit and each visit to s2 left it unchanged. The fifth arrival at s1 dropped the frame at zero. That is eight forwards before the drop, compared with four when both switches decrement the budget.

### Rollout options

A new EtherType makes the two wire layouts unambiguous. First deploy dual-format parsers on every switch and receiver while senders still use the old EtherType. Enable new-format sending per verified path, monitor drops, then retire the old format. A rollback can switch senders back to the old format while both remain supported. The tradeoff is a second parser path and two formats to operate during the transition. For this layout change, I would choose this approach.

A second option is to isolate upgraded devices into a domain with controlled borders. Use the new layout only inside it and translate or terminate encapsulation at the border. This retains the existing format outside the domain but requires careful path control and boundary handling. When crossing a legacy segment, a border cannot rely on the missing hop field to carry the remaining budget. That segment needs its own loop protection. Merely preserving the old exit ID offset does not preserve the old payload offset.

### Data plane and control plane

The Week 3 `check_paths()` approach can detect a repeated router or missing route in a proposed configuration before it is installed. It can explain which path is wrong, but it assumes its input reflects the forwarding tables in use. The data-plane budget bounds the lifetime of each packet even if the installed rules temporarily diverge from that model. It cannot diagnose a bad table, prove reachability, or tell an excessively long valid path from a cycle. Using both prevents known configuration errors and limits the impact of unexpected forwarding behavior.

### Cost at line rate

The change adds one byte to every tunnel frame and consumes eight bits of header storage plus a compare and conditional decrement in ingress. The existing lookup key and table size do not grow. A hardware compiler must fit the test, subtraction and lookup into the target's parser and match-action stages. Line rate is plausible if those operations fit the pipeline, but BMv2 does not demonstrate ASIC timing. Near the path MTU, the extra byte also has to come out of the payload budget or be accounted for in the link configuration.

## AI use

## Evidence files

| File | Evidence type |
| --- | --- |
| [loop-before.txt](evidence/loop-before.txt) | BMv2 counters and byte comparison on two finite paths with the original program |
| [delivery.txt](evidence/delivery.txt) | BMv2 tunnel and IPv4 delivery, including budget boundaries |
| [loop-after.txt](evidence/loop-after.txt) | BMv2 switch counters for the bounded cycle |
| [mixed.txt](evidence/mixed.txt) | BMv2 parser trace, capture bytes, receiver output, and switch counters |
