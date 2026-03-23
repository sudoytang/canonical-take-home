# Canonical Take-Home Exercise

## Repository Structure

```
.
├── discussion.typ       # Typst source for the submission PDF
├── exercise_1/
│   └── run.sh          # Shell script to build and run a bootable Linux system via QEMU
└── exercise_2/
    ├── go.mod
    ├── shred.go         # Shred(path) implementation
    └── shred_test.go    # Test cases
```

## Exercise 1: Bootable Linux via QEMU

```bash
cd exercise_1
./run.sh
```

Tested on Ubuntu 24.04. The script will install missing dependencies via `apt` (requires internet access and may prompt for `sudo`), then print `hello world` on the terminal.

## Exercise 2: Shred Tool in Go

```bash
cd exercise_2
go test ./...
```

Requires Go 1.18+.
