BUILD_DIR="build"
SOURCE_DIR="src"
PROGRAM_NAME="program"

if ! [[ -d $SOURCE_DIR ]]; then
  echo "No source files found!"
  exit 1
fi

find "$SOURCE_DIR" -type f -name "*.asm" |
while read -r asm_file; do
  rel_path="${asm_file#"$SOURCE_DIR"/}"
  obj_file="${rel_path%.asm}.o"
  target="$BUILD_DIR/$obj_file"

  mkdir -p "$(dirname "$target")"

  nasm -f elf32 -g -F dwarf -o "$target" "$asm_file"
  echo "Compiled $asm_file -> $target"
done

# shellcheck disable=SC2046
ld -m elf_i386 -o "$PROGRAM_NAME" $(find "$BUILD_DIR" -type f -name "*.o")
echo "Linked $BUILD_DIR/*.o -> $PROGRAM_NAME"

chmod +x $PROGRAM_NAME