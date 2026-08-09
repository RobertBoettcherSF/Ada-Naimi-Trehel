# Makefile
.PHONY: all test clean

GNAT = gnatmake
OBJ_DIR = obj
BIN_DIR = bin

all: $(BIN_DIR)/main$(BIN_DIR)/tests

$(BIN_DIR)/main: src/main.adb src/naimi_trehel.ads src/naimi_trehel.adb
	mkdir -p $(OBJ_DIR) $(BIN_DIR)$(GNAT) -o $(BIN_DIR)/main src/main.adb -Isrc -D$(OBJ_DIR)

$(BIN_DIR)/tests: tests.adb src/naimi_trehel.ads src/naimi_trehel.adb
	mkdir -p $(OBJ_DIR) $(BIN_DIR)$(GNAT) -o $(BIN_DIR)/tests tests.adb -Isrc -D$(OBJ_DIR)

test: $(BIN_DIR)/tests
	@echo "Running tests..."
	@$(BIN_DIR)/tests

clean:
	rm -rf $(OBJ_DIR)/*$(BIN_DIR)/*
