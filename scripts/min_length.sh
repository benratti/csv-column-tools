#!/bin/bash

# Usage : ./min_length.sh fichier.csv "nom_de_colonne"

csv_file="$1"
target_column="$2"

# Lire l'en-tête et trouver l'index (0-based)
header=$(head -1 "$csv_file")
col_index=$(echo "$header" | tr ',' '\n' | nl -v 0 | grep -F "\"$target_column\"" | awk '{print $1}')
col_name=$(echo "$header" | tr ',' '\n' | sed -n "$((col_index + 1))p" | sed 's/^"//;s/"$//')

if [ -z "$col_index" ]; then
  echo "Colonne \"$target_column\" introuvable."
  exit 1
fi

echo "Analyse de la colonne : \"$col_name\""

# Lire les données avec numéro de ligne, trouver longueur min et enregistrer les lignes
tail -n +2 "$csv_file" | \
awk -F',' -v idx="$col_index" '
  BEGIN { line_number = 2 }
  {
    value = $idx
    gsub(/^"|"$/, "", value)
    gsub(/^[ \t]+|[ \t]+$/, "", value)
    len = length(value)

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

    line_number++
  }
  END {
    print "Longueur minimale : " min
    print "Valeurs correspondantes (avec lignes) :"
    for (v in values) print "- " v " (lignes : " lines[v] ")"
  }
'


