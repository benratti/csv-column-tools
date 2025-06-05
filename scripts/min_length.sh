#!/bin/bash

print_help() {
  echo "Usage: $0 -f <file.csv> -c <column_name> [-s <separator>] [-m <mode>]"
  echo ""
  echo "Options:"
  echo "  -f, --file         CSV file to analyze"
  echo "  -c, --column       Name of the target column (case-sensitive)"
  echo "  -s, --separator    Field separator (default: , or '\\t' for tab)"
  echo "  -m, --mode         Mode: 'min' (default) or 'max' to calculate min/max length"
  echo "  -h, --help         Show this help message and exit"
}

# Default values
separator=','
mode="min"

# Parse args
csv_file=""
target_column=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -f|--file)
      csv_file="$2"
      shift 2
      ;;
    -c|--column)
      target_column="$2"
      shift 2
      ;;
    -s|--separator)
      separator="$2"
      shift 2
      ;;
    -m|--mode)
      mode="$2"
      if [[ "$mode" != "min" && "$mode" != "max" ]]; then
        echo "Error: mode must be 'min' or 'max'"
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    -*)
      echo "Unknown option: $1"
      print_help
      exit 1
      ;;
    *)
      echo "Unexpected argument: $1"
      print_help
      exit 1
      ;;
  esac
done

# Validate inputs
if [[ -z "$csv_file" || -z "$target_column" ]]; then
  echo "Error: Both --file and --column are required."
  print_help
  exit 1
fi

if [[ ! -f "$csv_file" ]]; then
  echo "Error: File '$csv_file' does not exist."
  exit 1
fi

# Decode \t for tab
if [[ "$separator" == "\\t" ]]; then
  separator=$'\t'
fi

# Extract column index (0-based)
col_index=$(head -n1 "$csv_file" | awk -v sep="$separator" -v col="$target_column" '
  {
    gsub(/^"|"$/, "", $0)
    n = split($0, fields, sep)
    for (i = 1; i <= n; i++) {
      gsub(/^"|"$/, "", fields[i])
      if (fields[i] == col) {
        print i - 1
        exit
      }
    }
    exit 2
  }
')

if [[ $? -ne 0 || -z "$col_index" ]]; then
  echo "Error: Column \"$target_column\" not found in the file."
  exit 1
fi

echo "Analyzing column: \"$target_column\" (index $col_index) in mode: $mode"

# Process the file with awk
tail -n +2 "$csv_file" | awk -v idx="$col_index" -v sep="$separator" -v mode="$mode" '
  BEGIN { line_number = 2 }
  {
    gsub(/^"|"$/, "", $0)
    n = split($0, fields, sep)

    if (idx + 1 > n) next

    value = fields[idx + 1]
    gsub(/^"|"$/, "", value)
    gsub(/^[ \t]+|[ \t]+$/, "", value)
    len = length(value)

    if (mode == "min") {
      if (min == "" || len < min) {
        min = len
        delete values
        delete lines
        values[value] = 1
        lines[value] = line_number
      } else if (len == min) {
        values[value] = 1
        lines[value] = lines[value] " " line_number
      }
    } else if (mode == "max") {
      if (max == "" || len > max) {
        max = len
        delete values
        delete lines
        values[value] = 1
        lines[value] = line_number
      } else if (len == max) {
        values[value] = 1
        lines[value] = lines[value] " " line_number
      }
    }

    line_number++
  }
  END {
    if (mode == "min") {
      print "Minimum length: " min
    } else {
      print "Maximum length: " max
    }
    print "Matching values (with line numbers):"
    for (v in values) print "- " v " (lines: " lines[v] ")"
  }
'
