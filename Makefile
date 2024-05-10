ASSEMBLY_FILES := main.asm string_utils.asm

OBJ_FILES := $(ASSEMBLY_FILES:.asm=.o)

AFLAGS := -f elf64

# DEBUG_FLAG := -g

TARGET=server

$(TARGET): $(OBJ_FILES)
	ld $(DEBUG_FLAG) -o $@ $^
	rm -rf $(OBJ_FILES)

%.o: %.asm
	nasm $(DEBUG_FLAG) $(AFLAGS) -o $@ $<
