#!/bin/bash

# Usage : ./count_by_length.sh fichier.csv "nom_de_colonne"

csv_file="$1"
target_column="$2"

# Trouver l'index de la colonne (0-based)
header=$(head -1 "$csv_file")
col_index=$(echo "$header" | tr ',' '\n' | nl -v 0 | grep -F "\"$target_column\"" | awk '{print $1}')

if [ -z "$col_index" ]; then
  echo "Colonne \"$target_column\" introuvable."
  exit 1
fi

echo "Analyse de la colonne : \"$target_column\""
echo
echo "| Longueur | Nombre de valeurs |"
echo "|----------|-------------------|"

tail -n +2 "$csv_file" | \
awk -F',' -v idx="$col_index" '
  {
    value = $idx
    gsub(/^"|"$/, "", value)             # Supprimer guillemets au début/fin
    gsub(/^[ \t]+|[ \t]+$/, "", value)  # Trim espaces
    len = length(value)
    count[len]++
  }
  END {
    for (l in count) {
      print l "|" count[l]
    }
  }
' | sort -n | awk -F'|' '{ printf("| %7s | %17s |\n", $1, $2) }'

