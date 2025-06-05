#!/bin/bash

print_help() {
  cat << EOF
Usage: $0 [-f <file.csv>] -c <column_name> [-l <length>] [-n <min_length>] [-x <max_length>] [-s <separator>] [-o <output_format>]

Options:
  -f, --file           CSV file to process (optional, if omitted reads from stdin)
  -c, --column         Name of the target column (case-sensitive) (required)
  -l, --length         Exact length to filter rows by (mutually exclusive with --min-length or --max-length)
  -n, --min-length     Minimum length to filter rows by (inclusive)
  -x, --max-length     Maximum length to filter rows by (inclusive)
  -s, --separator      Field separator character (default: ,)
  -o, --output         Output format: markdown (md) (default), csv, json
  -h, --help           Display this help message and exit

Description:
  Prints rows where the value in the specified column matches the length filters:
    - If --length is specified alone, filters rows where length equals the given value.
    - If --min-length and/or --max-length are specified, filters rows with length >= min_length and/or length <= max_length.
    - You cannot combine --length with --min-length or --max-length.

Examples:
  $0 -f data.csv -c City -l 5
  $0 -f data.csv -c City -n 3 -x 7
  cat data.csv | $0 -c City -n 4 --output=json
EOF
}

# Defaults
csv_file=""
column_name=""
target_length=""
min_length=""
max_length=""
separator=','
output_format="markdown"

# Parse parameters
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file)
      csv_file="$2"
      shift 2
      ;;
    -c|--column)
      column_name="$2"
      shift 2
      ;;
    -l|--length)
      target_length="$2"
      shift 2
      ;;
    -n|--min-length)
      min_length="$2"
      shift 2
      ;;
    -x|--max-length)
      max_length="$2"
      shift 2
      ;;
    -s|--separator)
      separator="$2"
      shift 2
      ;;
    -o|--output)
      output_format="$2"
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

# Validate required parameters
if [[ -z "$column_name" ]]; then
  echo "Error: Missing required parameter --column."
  print_help
  exit 1
fi

# Check conflicting length options
if [[ -n "$target_length" && ( -n "$min_length" || -n "$max_length" ) ]]; then
  echo "Error: --length cannot be combined with --min-length or --max-length."
  exit 1
fi

if [[ -z "$target_length" && -z "$min_length" && -z "$max_length" ]]; then
  echo "Error: At least one length filter (--length or --min-length or --max-length) must be specified."
  print_help
  exit 1
fi

# Validate numeric values for lengths
re='^[0-9]+$'
for val in "$target_length" "$min_length" "$max_length"; do
  if [[ -n "$val" && ! $val =~ $re ]]; then
    echo "Error: Length values must be non-negative integers."
    exit 1
  fi
done

# Check min <= max if both specified
if [[ -n "$min_length" && -n "$max_length" ]]; then
  if (( min_length > max_length )); then
    echo "Error: --min-length cannot be greater than --max-length."
    exit 1
  fi
fi

# If file specified, check existence
if [[ -n "$csv_file" && ! -f "$csv_file" ]]; then
  echo "Error: File '$csv_file' not found."
  exit 1
fi

# Decode \t separator if needed
if [[ "$separator" == "\\t" ]]; then
  separator=$'\t'
fi

# Validate output format and normalize md -> markdown
case "$output_format" in
  markdown|md)
    output_format="markdown"
    ;;
  csv|json)
    # keep as is
    ;;
  *)
    echo "Error: Invalid output format '$output_format'. Allowed: markdown (md), csv, json."
    exit 1
    ;;
esac

clean_cell() {
  local val="$1"
  val="${val#\"}"
  val="${val%\"}"
  val="$(echo -e "${val}" | sed -e 's/^[ \t]*//;s/[ \t]*$//')"
  echo "$val"
}

# Read header line (from file or stdin)
if [[ -n "$csv_file" ]]; then
  IFS="$separator" read -r -a headers < <(head -1 "$csv_file")
else
  IFS= read -r header_line
  headers=()
  IFS="$separator" read -r -a headers <<< "$header_line"
fi

# Find target column index
target_index=""
for i in "${!headers[@]}"; do
  name=$(clean_cell "${headers[$i]}")
  if [[ "$name" == "$column_name" ]]; then
    target_index="$i"
    break
  fi
done

if [[ -z "$target_index" ]]; then
  echo "Error: Column \"$column_name\" not found in the CSV."
  exit 1
fi

# Prepare data input for awk:
if [[ -n "$csv_file" ]]; then
  data_stream=$(tail -n +2 "$csv_file")
else
  data_stream=$(cat)
fi

# Build awk length filter condition
awk_filter='
  val = $(idx + 1)
  gsub(/^"|"$/, "", val)
  gsub(/^[ \t]+|[ \t]+$/, "", val)
  len = length(val)
  pass = 1
'

if [[ -n "$target_length" ]]; then
  awk_filter+='
    if (len != target_len) pass = 0
  '
else
  if [[ -n "$min_length" ]]; then
    awk_filter+='
      if (len < min_len) pass = 0
    '
  fi
  if [[ -n "$max_length" ]]; then
    awk_filter+='
      if (len > max_len) pass = 0
    '
  fi
fi

# Output according to format
case "$output_format" in
  markdown)
    echo -n "| Line |"
    for col in "${headers[@]}"; do
      name=$(clean_cell "$col")
      echo -n " $name |"
    done
    echo
    echo -n "|------|"
    for _ in "${headers[@]}"; do
      echo -n "------|"
    done
    echo

    echo "$data_stream" | awk -v sep="$separator" -v idx="$target_index" \
      -v target_len="$target_length" -v min_len="$min_length" -v max_len="$max_length" \
      -v awk_filter="$awk_filter" '
      BEGIN { FS=sep; OFS="|"; line=2 }
      {
        '"$awk_filter"'
        if (pass) {
          printf("| %4d ", line)
          for (i = 1; i <= NF; i++) {
            cell = $i
            gsub(/^"|"$/, "", cell)
            gsub(/^[ \t]+|[ \t]+$/, "", cell)
            printf("| %s ", cell)
          }
          print "|"
        }
        line++
      }
    '
    ;;
  csv)
    echo -n "Line$separator"
    for i in "${!headers[@]}"; do
      name=$(clean_cell "${headers[$i]}")
      echo -n "$name"
      [[ $i -lt $((${#headers[@]}-1)) ]] && echo -n "$separator" || echo
    done

    echo "$data_stream" | awk -v sep="$separator" -v idx="$target_index" \
      -v target_len="$target_length" -v min_len="$min_length" -v max_len="$max_length" \
      -v awk_filter="$awk_filter" '
      BEGIN { FS=sep; OFS=sep; line=2 }
      {
        '"$awk_filter"'
        if (pass) {
          printf("%d%s", line, OFS)
          for (i = 1; i <= NF; i++) {
            cell = $i
            gsub(/^"|"$/, "", cell)
            gsub(/^[ \t]+|[ \t]+$/, "", cell)
            printf("%s", cell)
            if (i < NF) printf("%s", OFS)
          }
          print ""
        }
        line++
      }
    '
    ;;
  json)
    echo "["
    echo "$data_stream" | awk -v sep="$separator" -v idx="$target_index" \
      -v target_len="$target_length" -v min_len="$min_length" -v max_len="$max_length" \
      -v awk_filter="$awk_filter" '
      function escape_json(str,    r) {
        gsub(/\\/,"\\\\",str)
        gsub(/"/,"\\\"",str)
        gsub(/\n/,"\\n",str)
        gsub(/\r/,"\\r",str)
        gsub(/\t/,"\\t",str)
        return str
      }
      BEGIN { FS=sep; line=2 }
      {
        '"$awk_filter"'
        if (pass) {
          json = sprintf("  {\"line\": %d", line)
          for (i=1; i<=NF; i++) {
            cell = $i
            gsub(/^"|"$/, "", cell)
            gsub(/^[ \t]+|[ \t]+$/, "", cell)
            cell = escape_json(cell)
            json = json sprintf(", \"%s\": \"%s\"", "'"${headers[i-1]//\"/}"'", cell)
          }
          json = json "}"
          print json
        }
        line++
      }
    ' | awk '
      NR==1 { printf "%s", $0; next }
      { printf ",\n%s", $0 }
      END { print "" }
    '
    echo "]"
    ;;
esac
