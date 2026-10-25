Run: 8 players with towns (2936 people in the biggest), 2 late joiners, 992 s. Steady window [178.0, 761.0] s.

Server CPU (one core = 100): steady mean 11.4, p95 37.9, max 99.5. Seconds pinned over 90: 2. Memory 5962 MB at start, 1615 at end, 6266 peak.
Bytes: server takes in 340.9 KB/s steady (peak 4762.6), sends out 1217.6 KB/s steady (peak 18808.4). Whole run: 316.1 MB in, 1023.5 MB out.
Server answer time (probe): {'n': 484, 'mean': 18.0, 'p50': 13.0, 'p95': 17.0, 'p99': 206.0, 'max': 616.0} ms; failed 0; over 1 s: 0; over 5 s: 0 of 484.
Sync lag on the wire (owner's copy in, neighbor's copy out): {'n': 820, 'mean': 0.5, 'p50': 0.4, 'p95': 0.64, 'p99': 3.91, 'max': 9.51} s.
Neighbors' towns on screen at the end: behind by {'n': 72, 'mean': 404.0, 'p50': 467, 'p95': 614, 'p99': 623, 'max': 623} buildings.
Server loop steps over 100 ms: 18 (worst 704 ms) {'msg.hello': {'n': 2, 'max_ms': 704}, 'poll': {'n': 15, 'max_ms': 336}, 'receive': {'n': 1, 'max_ms': 113}}.
City lines in frames over 100 ms (most in any one, per bot): {'Bot1': 2.8, 'Bot2': 2.3, 'Bot3': 2.2, 'Bot4': 2.5, 'Bot5': 2.3, 'Bot6': 2.2, 'Bot7': 2.3, 'Bot8': 0.0, 'Late1': 2.2, 'Late2': 2.1} ms.

| player | people | p50 ms | p95 ms | worst ms | freezes >1 s | hitches >100 ms | dropped/back | KB/s up | KB/s down | CPU % | peak RSS MB |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Bot1 | 2367 | 617.3 | 1907.3 | 10581.0 | 167 | 1088 | 0/0 | 37.6 | 136.9 | 85 | 4245.7 |
| Bot2 | 2144 | 636.8 | 1871.5 | 10595.4 | 179 | 1061 | 0/0 | 34.4 | 138.4 | 85 | 3869.2 |
| Bot3 | 1400 | 703.4 | 1940.6 | 12889.4 | 182 | 1010 | 0/0 | 43.8 | 136.2 | 88 | 4012.2 |
| Bot4 | 2119 | 673.7 | 1772.4 | 12139.3 | 185 | 1051 | 0/0 | 39.3 | 136.7 | 86 | 3007.6 |
| Bot5 | 2345 | 651.6 | 1692.7 | 12469.3 | 160 | 1055 | 0/0 | 45.0 | 135.9 | 87 | 3935.9 |
| Bot6 | 2242 | 672.1 | 1669.6 | 13501.1 | 189 | 1030 | 0/0 | 46.7 | 134.9 | 89 | 5787.3 |
| Bot7 | 2936 | 354.0 | 1103.2 | 12960.1 | 96 | 1609 | 0/0 | 54.9 | 128.7 | 87 | 7124.6 |
| Bot8 | 2646 | 525.4 | 1689.5 | 16011.9 | 176 | 1176 | 0/0 | 36.5 | 138.9 | 84 | 8240.6 |
| Late1 | 225 | 235.8 | 608.8 | 3942.0 | 21 | 627 | 0/0 | 1.1 | 68.4 | 78 | 1535.5 |
| Late2 | 177 | 265.0 | 648.1 | 3778.9 | 15 | 652 | 0/0 | 1.6 | 62.5 | 80 | 1523.3 |

| joiner | late | welcome MB | hello to welcome s | bot's load s |
|---|---|---|---|---|
| Bot1 |  | 5.11 | 0.03 | 32.18 |
| Bot2 |  | 5.15 | 0.03 | 28.42 |
| Bot3 |  | 5.43 | 0.03 | 27.45 |
| Bot4 |  | 5.23 | 0.03 | 32.54 |
| Bot5 |  | 5.65 | 0.03 | 34.86 |
| Bot6 |  | 6.28 | 0.08 | 47.13 |
| Bot7 |  | 5.43 | 0.04 | 34.94 |
| Bot8 |  | 5.45 | 0.1 | 46.18 |
| Late1 | yes | 0.03 | 0.31 | 8.04 |
| Late2 | yes | 0.03 | 0.63 | 10.82 |

Problems: none
