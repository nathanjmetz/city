Run: 4 players with towns (6173 people in the biggest), 2 late joiners, 1431 s. Steady window [97.1, 1338.5] s.

Server CPU (one core = 100): steady mean 9.2, p95 47.5, max 99.5. Seconds pinned over 90: 14. Memory 2939 MB at start, 2594 at end, 3911 peak.
Bytes: server takes in 197.9 KB/s steady (peak 5379.1), sends out 505.0 KB/s steady (peak 26894.3). Whole run: 280.6 MB in, 728.4 MB out.
Server answer time (probe): {'n': 664, 'mean': 119.0, 'p50': 13.0, 'p95': 713.0, 'p99': 1190.0, 'max': 7583.0} ms; failed 0; over 1 s: 14; over 5 s: 1 of 664.
Sync lag on the wire (owner's copy in, neighbor's copy out): {'n': 342, 'mean': 2.63, 'p50': 0.15, 'p95': 5.88, 'p99': 68.54, 'max': 92.21} s.
Neighbors' towns on screen at the end: behind by {'n': 20, 'mean': 23.0, 'p50': 22, 'p95': 50, 'p99': 50, 'max': 50} buildings.

| player | people | p50 ms | p95 ms | worst ms | freezes >1 s | hitches >100 ms | dropped/back | KB/s up | KB/s down | CPU % | peak RSS MB |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Bot1 | 6173 | 219.1 | 566.2 | 107388.3 | 92 | 2315 | 0/0 | 50.7 | 111.1 | 97 | 4474.0 |
| Bot2 | 5836 | 227.6 | 579.9 | 131489.8 | 85 | 2244 | 0/0 | 49.7 | 115.1 | 97 | 4834.2 |
| Bot3 | 4560 | 252.4 | 595.3 | 109404.2 | 90 | 2073 | 0/0 | 47.5 | 115.0 | 97 | 5013.6 |
| Bot4 | 5611 | 224.1 | 596.9 | 107185.2 | 91 | 2111 | 0/0 | 49.8 | 113.5 | 96 | 4902.8 |
| Late1 | 0 | 87.8 | 137.8 | 62726.0 | 10 | 91 | 0/0 | 0.3 | 30.7 | 90 | 2016.0 |
| Late2 | 0 | 81.7 | 112.9 | 104642.9 | 11 | 101 | 0/0 | 0.1 | 19.5 | 97 | 2341.1 |

| joiner | late | welcome MB | hello to welcome s | bot's load s |
|---|---|---|---|---|
| Bot1 |  | 10.07 | 0.3 | 25.7 |
| Bot2 |  | 10.05 | 1.34 | 27.03 |
| Bot3 |  | 10.14 | 0.38 | 26.75 |
| Bot4 |  | 9.99 | 0.37 | 30.52 |
| Late1 | yes | 7.8 | 8.32 | 15.94 |
| Late2 | yes | 7.86 | 6.32 | 14.07 |

Problems: none
