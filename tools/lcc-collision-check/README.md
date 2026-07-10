# LCC Collision Check

Small Java utility to detect collisions for numeric cluster IDs derived from logical cluster IDs (LCC).

It uses this formula:

```java
Math.abs(logicalClusterId.hashCode() % 10240)
```

## Files

- `LccCollisionCheck.java`: main program
- `lcc-list.txt`: optional input file with one LCC per line

## Compile

```bash
cd tools/lcc-collision-check
javac LccCollisionCheck.java
```

## Run

### 1) Pass LCC values as arguments

```bash
java LccCollisionCheck lcc1 lcc2 lcc3
```

### 2) Read LCC values from a file

```bash
java LccCollisionCheck --file lcc-list.txt
```

### 3) Read LCC values from stdin

```bash
cat lcc-list.txt | java LccCollisionCheck
```

## Output

For each input LCC, the tool prints the computed numeric cluster ID.

Then it prints a collision report:

- If no collisions exist: `No collisions found.`
- If collisions exist: lines like

```text
COLLISION numericClusterId=1234 lccs=[lcc-a, lcc-b]
```

## Exit Codes

- `0`: no collisions
- `2`: collisions found
- `1`: invalid input (for example, no LCC values provided)
