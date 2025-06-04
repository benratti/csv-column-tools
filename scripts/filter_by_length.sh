#!/bin/bash

# Usage :
# ./filter_by_length.sh fichier.csv "Nom de la colonne" longueur

csv_file="$1"
column_name="$2"
target_length="$3"

# Lire l'en-tête du fichier et déterminer l'index de la colonne cible
IFS=',' read -r -a headers <<< "$(head -1 "$csv_file")"
target_index=""
for i in "${!headers[@]}"; do
  name=$(echo "${headers[$i]}" | sed 's/^"//;s/"$//')
  if [[ "$name" == "$column_name" ]]; then
    target_index="$i"
    break
  fi
done

if [ -z "$target_index" ]; then
  echo "Colonne \"$column_name\" introuvable."
  exit 1
fi

# Affichage de l’en-tête Markdown
echo -n "| Ligne |"
for col in "${headers[@]}"; do
  name=$(echo "$col" | sed 's/^"//;s/"$//')
  echo -n " $name |"
done
echo

# Ligne de séparation Markdown
echo -n "|-------|"
for _ in "${headers[@]}"; do
  echo -n "-------|"
done
echo

# Traitement des lignes
tail -n +2 "$csv_file" | \
awk -F',' -v idx="$target_index" -v len="$target_length" '
  BEGIN { OFS="|"; line=2 }
  {
    val = $idx
    gsub(/^"|"$/, "", val)
    gsub(/^[ \t]+|[ \t]+$/, "", val)

    if (length(val) == len) {
      printf("| %5d ", line)
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

