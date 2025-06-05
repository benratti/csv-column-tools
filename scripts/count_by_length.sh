#!/bin/bash

print_help() {
  cat << EOF
Usage: $0 [options]

Options:
  -f, --file FILE         Input file (CSV or JSON). If not specified, reads stdin.
  -c, --column COLUMN     Target column name (required).
  -s, --separator SEP     CSV separator (default: auto-detect).
  -o, --output FORMAT     Output format: markdown (default), md, json, or csv.
  -h, --help             Show this help message.

Description:
  Counts the number of lines grouped by the length of the values in the specified column.
  Supports CSV or JSON input (auto-detected).

Examples:
  $0 -f data.csv -c City
  cat data.json | $0 -c Name -o csv
EOF
}

clean_cell() {
  local val="$1"
  val="${val#\"}"
  val="${val%\"}"
  val="$(echo -e "$val" | sed -e 's/^[ \t]*//;s/[ \t]*$//')"
  echo "$val"
}

detect_separator() {
  local header_line="$1"
  local seps=',' ';' $'\t' '|'
  local max_count=0
  local chosen_sep=','
  for sep in "${seps[@]}"; do
    count=$(grep -o "$sep" <<< "$header_line" | wc -l)
    if (( count > max_count )); then
      max_count=$count
      chosen_sep=$sep
    fi
  done
  echo "$chosen_sep"
}

process_csv() {
  local input="$1"

  IFS= read -r header_line < <(head -n1 <<< "$input")

  # Detect separator if not specified
  if [[ -z "$separator" ]]; then
    separator=$(detect_separator "$header_line")
  fi

  IFS="$separator" read -ra headers <<< "$header_line"

  col_index=""
  for i in "${!headers[@]}"; do
    name=$(clean_cell "${headers[i]}")
    if [[ "$name" == "$column_name" ]]; then
      col_index=$i
      break
    fi
  done

  if [[ -z "$col_index" ]]; then
    echo "Error: Column '$column_name' not found in CSV header."
    exit 1
  fi

  case "$output_format" in
    markdown|md)
      # Collect counts in awk and print aligned markdown table nicely
      tail -n +2 <<< "$input" | \
      awk -v FS="$separator" -v idx=$((col_index+1)) '
        {
          val = $idx
          gsub(/^"|"$/, "", val)
          gsub(/^[ \t]+|[ \t]+$/, "", val)
          len = length(val)
          count[len]++
        }
        END {
          printf("| %-7s | %-13s |\n", "Length", "Count")
          printf("|%s|%s|\n", "---------", "-------------")
          n = asorti(count, sorted_lengths)
          for (i=1; i<=n; i++) {
            l = sorted_lengths[i]
            printf("| %-7d | %-13d |\n", l, count[l])
          }
        }
      '
      ;;
    json)
      echo "["
      first=1
      tail -n +2 <<< "$input" | \
      awk -v FS="$separator" -v idx=$((col_index+1)) '
        {
          val = $idx
          gsub(/^"|"$/, "", val)
          gsub(/^[ \t]+|[ \t]+$/, "", val)
          len = length(val)
          count[len]++
        }
        END {
          for (l in count) {
            if (first == 0) printf(",\n");
            printf("{\"length\":%d,\"count\":%d}", l, count[l])
            first = 0
          }
        }
      '
      echo
      echo "]"
      ;;
    csv)
      echo "length,count"
      tail -n +2 <<< "$input" | \
      awk -v FS="$separator" -v idx=$((col_index+1)) '
        {
          val = $idx
          gsub(/^"|"$/, "", val)
          gsub(/^[ \t]+|[ \t]+$/, "", val)
          len = length(val)
          count[len]++
        }
        END {
          for (l in count) print l "," count[l]
        }
      ' | sort -n
      ;;
    *)
      echo "Error: Unsupported output format: $output_format. Use markdown, md, json or csv."
      exit 1
      ;;
  esac
}

process_json() {
  local input="$1"

  # jq is required
  if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required to process JSON input."
    exit 1
  fi

  # Extract counts grouped by length of target column values
  counts=$(jq -r --arg col "$column_name" '
    map(.[$col] // "") | 
    map(tostring) | 
    map(length) | 
    group_by(.) | 
    map({length: .[0], count: length})' <<< "$input")

  if [[ -z "$counts" ]]; then
    echo "Error: Could not find or parse the column '$column_name' in JSON."
    exit 1
  fi

  case "$output_format" in
    markdown|md)
      echo "| Length | Count |"
      echo "|--------|-------|"
      jq -r '.[] | "| " + (.length|tostring) + " | " + (.count|tostring) + " |"' <<< "$counts"
      ;;
    json)
      jq '.' <<< "$counts"
      ;;
    csv)
      echo "length,count"
      jq -r '.[] | "\(.length),\(.count)"' <<< "$counts"
      ;;
    *)
      echo "Error: Unsupported output format: $output_format. Use markdown, md, json or csv."
      exit 1
      ;;
  esac
}

# Defaults
csv_file=""
column_name=""
separator=""
output_format="markdown"

# Parse parameters
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file) csv_file="$2"; shift 2 ;;
    -c|--column) column_name="$2"; shift 2 ;;
    -s|--separator) separator="$2"; shift 2 ;;
    -o|--output) output_format="$2"; shift 2 ;;
    -h|--help) print_help; exit 0 ;;
    *) echo "Unknown option: $1"; print_help; exit 1 ;;
  esac
done

if [[ -z "$column_name" ]]; then
  echo "Error: --column is required."
  print_help
  exit 1
fi

# Read input either from file or stdin
if [[ -n "$csv_file" ]]; then
  if [[ ! -f "$csv_file" ]]; then
    echo "Error: File '$csv_file' not found."
    exit 1
  fi
  input_content=$(cat "$csv_file")
else
  input_content=$(cat)
fi

# Detect input format (JSON or CSV)
input_first_char="${input_content:0:1}"
if [[ "$input_first_char" == "[" || "$input_first_char" == "{" ]]; then
  # JSON input
  process_json "$input_content"
else
  # CSV input
  process_csv "$input_content"
fi
