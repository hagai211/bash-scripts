#!/usr/bin/bash
# --- Initialize default options ---
verbose=0
recursive=0

while getopts ":vr" opt; do 
  case $opt in
    v)
      verbose=1 # if -v is used 
      ;;
    r)
      recursive=1 # if -r is used
      ;;
    *)
      echo "Usage: $0 [-v] [-r] file [files...]" # if an unsupported flag is used
      exit 1
      ;;
  esac
done
shift $((OPTIND-1)) # address only the files and folders

if [ "$#" -lt 1 ]; then # Checks that at least one file/directory argument remains
  echo "Usage: $0 [-v] [-r] file [files...]"
  exit 1
fi

# --- Function: process_file ---
# Processes a single file
process_file() {
  local file="$1" #initialize file variable to contain the first argument passed to the function
  [ ! -f "$file" ] && return 1 # checks if its a regular file if it's not return 1

  local file_info
  file_info=$(file -b "$file") # file_info contain the output of file -b "$file"
  
  # Detect compression type.
  local compression_type="none"
  if echo "$file_info" | grep -q "gzip compressed data"; then # grep -q flag for quiet grep (no output)
    compression_type="gzip"
  elif echo "$file_info" | grep -q "bzip2 compressed data"; then
    compression_type="bzip2"
  elif echo "$file_info" | grep -q "Zip archive data"; then
    compression_type="zip"
  elif echo "$file_info" | grep -q "compress'd data"; then
    compression_type="compress"
  fi
  
  # Verbose output.
  if [ "$verbose" -eq 1 ]; then
    if [ "$compression_type" = "none" ]; then
      echo "Ignoring $(basename "$file")"
    else
      echo "Unpacking $(basename "$file")..."
    fi
  fi
  
  [ "$compression_type" = "none" ] && return 1
  
  local dir
  dir=$(dirname "$file") # directory path containing the file
  local output_file=""
  local ret=0
  
  case "$compression_type" in
    gzip)
      local orig
      orig=$(gzip -lv "$file" 2>/dev/null | awk 'NR==2 {print $9}')  # extract the original name from the header
      # If the original name starts with a slash, it's an absolute path; use only the basename.
      if [[ "$orig" == /* ]]; then
        orig=$(basename "$orig")
      fi
      if [ -n "$orig" ] && [ "$orig" != "-" ]; then 
        output_file="$dir/${orig}.out"  # Append .out to the extracted (and now possibly shortened) original name.
      else
        local base
        base=$(basename "$file")
        base="${base%.gz}"
        base="${base%.gzip}"
        output_file="$dir/$base"
      fi


      gunzip -c "$file" > "$output_file" 2>/dev/null # Redirect file descriptor 2(standard error) to /dev/null, eliminating any irrelevant output
      ret=$? # insert the exit code of the gunzip to ret variable
      ;;
    bzip2)
      local base
      base=$(basename "$file")
      if [[ "$file" == *.bz2 ]]; then
        base="${base%.bz2}"
      else
        base="$base.out"
      fi
      output_file="$dir/$base"
      bunzip2 -c "$file" > "$output_file" 2>/dev/null
      ret=$?
      ;;
    compress)
      local base
      base=$(basename "$file")
      if [[ "$file" == *.Z ]]; then
        base="${base%.Z}"
      else
        base="$base.out"
      fi
      output_file="$dir/$base"
      uncompress -c "$file" > "$output_file" 2>/dev/null
      ret=$?
      ;;
    zip)
      unzip -o "$file" -d "$dir" > /dev/null 2>&1 # For zip archives, extract all contents into the parent folder.
      ret=$?
      ;;
  esac
  
  return $ret
}

# --- Function: process_item ---
# Processes a file or directory.
process_item() {
  local item="$1"
  
  if [ -d "$item" ]; then
    if [ "$recursive" -eq 1 ]; then
      for f in "$item"/*; do
        [ -e "$f" ] && process_item "$f" # calles itself recursvely for each file
      done
    else
      for f in "$item"/*; do
        [ -f "$f" ] && process_item "$f" # if the item is a file/ we reached a file
      done
    fi
    return
  fi
  
  process_file "$item"
  if [ $? -eq 0 ]; then
    success_count=$((success_count + 1))
  else
    failure_count=$((failure_count + 1))
  fi
}

# --- Main Processing ---
success_count=0
failure_count=0

for arg in "$@"; do
  process_item "$(realpath "$arg")" # recusion starts and iterates on each argument passed to the script absolute path is used to avoid duplicates
done

echo "Decompressed ${success_count} archive(s)"
exit $failure_count
