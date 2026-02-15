#!/usr/bin/env bash

# ============================================================================
# test_senscritique_csv.sh
# ============================================================================
# Teste la validité d'un CSV SensCritique généré
# Usage: ./test_senscritique_csv.sh output.csv
# ============================================================================

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <output.csv>" >&2
    exit 1
fi

CSV_FILE="$1"

if [ ! -f "$CSV_FILE" ]; then
    echo "❌ Erreur: Le fichier '$CSV_FILE' n'existe pas" >&2
    exit 1
fi

echo "🔍 Test du fichier CSV: $CSV_FILE"
echo "═══════════════════════════════════════════════════"

# Compteurs
TOTAL_ERRORS=0
TOTAL_WARNINGS=0
TOTAL_LINES=0

# Test 1: Vérifier l'encodage UTF-8
echo ""
echo "📋 Test 1: Encodage UTF-8"
if command -v file >/dev/null 2>&1; then
    if file "$CSV_FILE" | grep -q "UTF-8"; then
        echo "   ✓ Encodage UTF-8 détecté"
    else
        echo "   ⚠️  Attention: L'encodage n'est pas UTF-8"
        TOTAL_WARNINGS=$((TOTAL_WARNINGS + 1))
    fi
else
    echo "   ⚠️  Commande 'file' non disponible, test ignoré"
fi

# Test 2: Vérifier le header
echo ""
echo "📋 Test 2: Header CSV"
EXPECTED_HEADER="universe,title,release_date,rating,is_wishlisted,is_recommended,is_done"
ACTUAL_HEADER=$(head -n 1 "$CSV_FILE")

if [ "$ACTUAL_HEADER" = "$EXPECTED_HEADER" ]; then
    echo "   ✓ Header correct"
else
    echo "   ❌ Header invalide"
    echo "      Attendu: $EXPECTED_HEADER"
    echo "      Trouvé:  $ACTUAL_HEADER"
    TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
fi

# Test 3: Compter les lignes
echo ""
echo "📋 Test 3: Nombre de lignes"
TOTAL_LINES=$(tail -n +2 "$CSV_FILE" | wc -l | tr -d ' ')
echo "   ℹ️  $TOTAL_LINES films trouvés"

if [ "$TOTAL_LINES" -eq 0 ]; then
    echo "   ⚠️  Aucun film dans le CSV"
    TOTAL_WARNINGS=$((TOTAL_WARNINGS + 1))
fi

# Test 4: Vérifier la structure de chaque ligne
echo ""
echo "📋 Test 4: Validation des lignes"

awk -F',' '
BEGIN {
    errors = 0
    warnings = 0
    line_num = 0
}

NR == 1 { next }

{
    line_num++
    
    # Parser CSV avec gestion des guillemets
    n_fields = 0
    field = ""
    in_quotes = 0
    
    for (i = 1; i <= length($0); i++) {
        char = substr($0, i, 1)
        
        if (char == "\"") {
            in_quotes = !in_quotes
        } else if (char == "," && !in_quotes) {
            fields[++n_fields] = field
            field = ""
        } else {
            field = field char
        }
    }
    fields[++n_fields] = field
    
    if (n_fields != 7) {
        print "   ❌ Ligne " line_num ": Nombre de colonnes incorrect (" n_fields " au lieu de 7)"
        errors++
        next
    }
    
    universe = fields[1]
    title = fields[2]
    year = fields[3]
    rating = fields[4]
    wishlisted = fields[5]
    recommended = fields[6]
    done = fields[7]
    
    if (universe != "movie") {
        print "   ❌ Ligne " line_num ": universe doit être \"movie\", trouvé: \"" universe "\""
        errors++
    }
    
    gsub(/^[[:space:]]*"|"[[:space:]]*$/, "", title)
    if (title == "") {
        print "   ❌ Ligne " line_num ": title est vide"
        errors++
    }
    
    if (year !~ /^[0-9]{4}$/) {
        print "   ❌ Ligne " line_num ": release_date invalide: \"" year "\""
        errors++
    }
    
    # Validation du rating: vide OU un nombre entier entre 1 et 10
    if (rating != "") {
        # Vérifier que c est un nombre
        if (rating !~ /^[0-9]+$/) {
            print "   ❌ Ligne " line_num ": rating invalide (pas un nombre): \"" rating "\""
            errors++
        } else {
            # Convertir en nombre et vérifier la plage
            rating_num = rating + 0
            if (rating_num < 1 || rating_num > 10) {
                print "   ❌ Ligne " line_num ": rating hors limites: " rating " (doit être entre 1 et 10)"
                errors++
            }
        }
    }
    
    if (wishlisted != "true" && wishlisted != "false") {
        print "   ❌ Ligne " line_num ": is_wishlisted invalide: \"" wishlisted "\""
        errors++
    }
    
    if (recommended != "true" && recommended != "false") {
        print "   ❌ Ligne " line_num ": is_recommended invalide: \"" recommended "\""
        errors++
    }
    
    if (done != "true" && done != "false") {
        print "   ❌ Ligne " line_num ": is_done invalide: \"" done "\""
        errors++
    }
    
    if (wishlisted == "true" && done == "true") {
        print "   ⚠️  Ligne " line_num ": Film à la fois wishlisted ET done (\"" title "\")"
        warnings++
    }
    
    if (done == "false" && rating != "") {
        print "   ⚠️  Ligne " line_num ": Film non vu avec une note (\"" title "\")"
        warnings++
    }
}

END {
    print ""
    print "   Erreurs:        " errors
    print "   Avertissements: " warnings
    exit errors
}
' "$CSV_FILE"

AWK_EXIT=$?
TOTAL_ERRORS=$((TOTAL_ERRORS + AWK_EXIT))

# Test 5: Vérifier les doublons
echo ""
echo "📋 Test 5: Détection des doublons"

DUPLICATES=$(tail -n +2 "$CSV_FILE" | awk -F',' '
{
    n_fields = 0
    field = ""
    in_quotes = 0
    
    for (i = 1; i <= length($0); i++) {
        char = substr($0, i, 1)
        
        if (char == "\"") {
            in_quotes = !in_quotes
        } else if (char == "," && !in_quotes) {
            fields[++n_fields] = field
            field = ""
        } else {
            field = field char
        }
    }
    fields[++n_fields] = field
    
    if (n_fields >= 3) {
        title = fields[2]
        year = fields[3]
        gsub(/^[[:space:]]*"|"[[:space:]]*$/, "", title)
        key = title "|" year
        
        count[key]++
        if (count[key] == 2) {
            print title " (" year ")"
        }
    }
}
')

if [ -n "$DUPLICATES" ]; then
    echo "   ❌ Doublons détectés:"
    echo "$DUPLICATES" | sed 's/^/      /'
    TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
else
    echo "   ✓ Aucun doublon détecté"
fi

# Test 6: Statistiques
echo ""
echo "📋 Test 6: Statistiques"

tail -n +2 "$CSV_FILE" | awk -F',' '
{
    n_fields = 0
    field = ""
    in_quotes = 0
    
    for (i = 1; i <= length($0); i++) {
        char = substr($0, i, 1)
        
        if (char == "\"") {
            in_quotes = !in_quotes
        } else if (char == "," && !in_quotes) {
            fields[++n_fields] = field
            field = ""
        } else {
            field = field char
        }
    }
    fields[++n_fields] = field
    
    if (n_fields >= 7) {
        if (fields[4] != "") with_rating++
        if (fields[5] == "true") wishlisted++
        if (fields[6] == "true") recommended++
        if (fields[7] == "true") done++
    }
}

END {
    print "   • Films vus (is_done):          " done
    print "   • Films en wishlist:            " wishlisted
    print "   • Films recommandés (likes):    " recommended
    print "   • Films avec note:              " with_rating
}
'

# Test 7: Échantillon des données
echo ""
echo "📋 Test 7: Échantillon (5 premières lignes)"
echo ""
head -n 6 "$CSV_FILE" | tail -n 5 | awk -F',' '
{
    n_fields = 0
    field = ""
    in_quotes = 0
    
    for (i = 1; i <= length($0); i++) {
        char = substr($0, i, 1)
        
        if (char == "\"") {
            in_quotes = !in_quotes
        } else if (char == "," && !in_quotes) {
            fields[++n_fields] = field
            field = ""
        } else {
            field = field char
        }
    }
    fields[++n_fields] = field
    
    title = fields[2]
    year = fields[3]
    rating = fields[4]
    done = fields[7]
    
    gsub(/^[[:space:]]*"|"[[:space:]]*$/, "", title)
    
    if (length(title) > 40) {
        title = substr(title, 1, 37) "..."
    }
    
    printf "   • %-40s (%s) ", title, year
    if (rating != "") {
        printf "[Note: %2s/10] ", rating
    } else {
        printf "[Pas de note] "
    }
    if (done == "true") {
        printf "✓ Vu"
    } else {
        printf "☐ À voir"
    }
    printf "\n"
}
'

# Résultat final
echo ""
echo "═══════════════════════════════════════════════════"
if [ $TOTAL_ERRORS -eq 0 ]; then
    echo "✅ SUCCÈS: Le CSV est valide"
    if [ $TOTAL_WARNINGS -gt 0 ]; then
        echo "⚠️  $TOTAL_WARNINGS avertissement(s) détecté(s)"
    fi
    exit 0
else
    echo "❌ ÉCHEC: $TOTAL_ERRORS erreur(s) détectée(s)"
    exit 1
fi