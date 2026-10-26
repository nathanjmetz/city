Run: 8 players with towns (3852 people in the biggest), 2 late joiners, 937 s. Steady window [177.5, 724.0] s.

Server CPU (one core = 100): steady mean 10.2, p95 27.7, max 60.7. Seconds pinned over 90: 0. Memory 4138 MB at start, 1004 at end, 4355 peak.
Bytes: server takes in 318.1 KB/s steady (peak 5457.7), sends out 1205.1 KB/s steady (peak 13815.1). Whole run: 283.6 MB in, 933.7 MB out.
Server answer time (probe): {'n': 459, 'mean': 13.0, 'p50': 13.0, 'p95': 17.0, 'p99': 44.0, 'max': 140.0} ms; failed 0; over 1 s: 0; over 5 s: 0 of 459.
Sync lag on the wire (owner's copy in, neighbor's copy out): {'n': 1073, 'mean': 0.31, 'p50': 0.28, 'p95': 0.43, 'p99': 0.63, 'max': 8.72} s.
Neighbors' towns on screen at the end: behind by {'n': 72, 'mean': 337.0, 'p50': 412, 'p95': 544, 'p99': 588, 'max': 588} buildings.
Server loop steps over 100 ms: 6 (worst 382 ms) {'msg.hello': {'n': 2, 'max_ms': 382}, 'poll': {'n': 3, 'max_ms': 157}, 'jobs': {'n': 1, 'max_ms': 110}}.
City lines in frames over 100 ms (most in any one, per bot): {'Bot1': 2.1, 'Bot2': 2.0, 'Bot3': 3.1, 'Bot4': 3.2, 'Bot5': 2.2, 'Bot6': 2.2, 'Bot7': 2.1, 'Bot8': 4.4, 'Late1': 5.6, 'Late2': 7.9} ms.

| player | people | p50 ms | p95 ms | worst ms | freezes >1 s | hitches >100 ms | dropped/back | KB/s up | KB/s down | CPU % | peak RSS MB |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Bot1 | 3719 | 373.2 | 951.7 | 10078.2 | 73 | 1609 | 0/0 | 40.8 | 135.2 | 79 | 4767.2 |
| Bot2 | 3852 | 387.3 | 1010.6 | 10418.1 | 77 | 1608 | 0/0 | 36.0 | 136.2 | 81 | 4111.7 |
| Bot3 | 3538 | 433.6 | 1148.1 | 7720.6 | 94 | 1506 | 0/0 | 41.8 | 133.7 | 83 | 3031.6 |
| Bot4 | 3585 | 415.7 | 1027.6 | 7973.1 | 79 | 1533 | 0/0 | 40.2 | 134.4 | 83 | 3332.4 |
| Bot5 | 3546 | 422.3 | 1022.8 | 8428.9 | 76 | 1507 | 0/0 | 43.4 | 133.4 | 84 | 4513.8 |
| Bot6 | 3324 | 441.5 | 1213.2 | 8346.0 | 94 | 1406 | 0/0 | 41.2 | 134.8 | 86 | 4880.4 |
| Bot7 | 3554 | 429.8 | 1220.0 | 8256.8 | 95 | 1461 | 0/0 | 37.5 | 135.9 | 86 | 6256.3 |
| Bot8 | 3231 | 407.1 | 1133.1 | 8788.9 | 104 | 1547 | 0/0 | 34.3 | 136.9 | 82 | 6810.9 |
| Late1 | 379 | 213.2 | 472.4 | 2740.6 | 15 | 716 | 0/0 | 1.2 | 62.9 | 85 | 1356.1 |
| Late2 | 195 | 258.7 | 619.0 | 2245.6 | 12 | 683 | 0/0 | 1.7 | 61.7 | 79 | 1229.8 |

| joiner | late | welcome MB | hello to welcome s | bot's load s |
|---|---|---|---|---|
| Bot1 |  | 3.4 | 0.04 | 21.61 |
| Bot2 |  | 3.47 | 0.03 | 21.05 |
| Bot3 |  | 3.72 | 0.03 | 18.8 |
| Bot4 |  | 3.56 | 0.03 | 22.63 |
| Bot5 |  | 4.01 | 0.03 | 24.13 |
| Bot6 |  | 4.59 | 0.03 | 30.74 |
| Bot7 |  | 4.02 | 0.03 | 22.85 |
| Bot8 |  | 3.73 | 0.03 | 27.97 |
| Late1 | yes | 0.02 | 0.27 | 8.33 |
| Late2 | yes | 0.02 | 0.35 | 8.4 |

Problems: none
