# Optional: specify cross compiler with make CROSS_COMPILE=aarch64-none-linux-gnu-
CROSS_COMPILE ?=

# Compiler
CC := $(CROSS_COMPILE)gcc

# Flags
CFLAGS := -Wall -Wextra -g

# Source and Target
SRC := writer.c
TARGET := writer

# Default target
all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $(TARGET) $(SRC)

clean:
	rm -f writer