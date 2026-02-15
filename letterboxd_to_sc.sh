#!/usr/bin/env bash

# ============================================================================
# letterboxd_zip_to_senscritique.sh
# ============================================================================
# Convertit un export Letterboxd (ZIP) en CSV compatible SensCritique
# ============================================================================

set -e

VERSION="1.0.0"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction d'affichage
print_error() {
    echo -e "${RED}❌ Erreur:${NC} $1" >&2
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Fonction d'affichage du menu
show_menu() {
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║     Letterboxd → SensCritique CSV Converter v${VERSION}      ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Ce script convertit un export Letterboxd (ZIP) en CSV"
    echo "compatible avec l'import SensCritique."
    echo ""
    echo "Options:"
    echo "  1) Convertir un fichier ZIP"
    echo "  2) Afficher l'aide"
    echo "  3) Quitter"
    echo ""
}

# Fonction d'aide
show_help() {
    cat << EOF

╔════════════════════════════════════════════════════════════╗
║                         AIDE                               ║
╚════════════════════════════════════════════════════════════╝

UTILISATION:
  $0 [OPTIONS] <fichier.zip> <sortie.csv>
  
  OU en mode interactif:
  $0

OPTIONS:
  -h, --help     Afficher cette aide
  -v, --version  Afficher la version
  -q, --quiet    Mode silencieux (pas de sortie sauf erreurs)

EXEMPLE:
  $0 letterboxd_export.zip senscritique.csv

FORMAT D'ENTRÉE (ZIP Letterboxd):
  • watchlist.csv         (films à voir)
  • ratings.csv           (films notés)
  • likes/films.csv       (films likés)

FORMAT DE SORTIE (CSV SensCritique):
  universe,title,release_date,rating,is_wishlisted,is_recommended,is_done

RÈGLES DE FUSION:
  • watchlist → is_wishlisted=true, is_done=false
  • ratings   → is_done=true, rating=note*2
  • likes     → is_recommended=true

EOF
}

# Vérification des dépendances
check_dependencies() {
    local missing=()
    
    if ! command -v unzip >/dev/null 2>&1; then
        missing+=("unzip")
    fi
    
    if ! command -v awk >/dev/null 2>&1; then
        missing+=("awk")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Dépendances manquantes: ${missing[*]}"
        print_info "Installez-les avec: sudo apt-get install ${missing[*]}"
        return 1
    fi
    
    return 0
}

# Vérification du fichier ZIP
validate_zip() {
    local zip_file="$1"
    
    if [ ! -f "$zip_file" ]; then
        print_error "Le fichier '$zip_file' n'existe pas"
        return 1
    fi
    
    if ! unzip -t "$zip_file" >/dev/null 2>&1; then
        print_error "Le fichier '$zip_file' n'est pas un ZIP valide"
        return 1
    fi
    
    # Vérifier si au moins un fichier requis existe
    local has_data=0
    if unzip -l "$zip_file" | grep -q "watchlist.csv"; then
        has_data=1
    fi
    if unzip -l "$zip_file" | grep -q "ratings.csv"; then
        has_data=1
    fi
    if unzip -l "$zip_file" | grep -q "likes/films.csv"; then
        has_data=1
    fi
    
    if [ $has_data -eq 0 ]; then
        print_error "Le ZIP ne contient aucun fichier Letterboxd valide"
        print_info "Fichiers attendus: watchlist.csv, ratings.csv, likes/films.csv"
        return 1
    fi
    
    return 0
}

# Fonction principale de conversion
convert_zip_to_csv() {
    local zip_file="$1"
    local output_csv="$2"
    local quiet="${3:-0}"
    
    [ $quiet -eq 0 ] && print_info "Lecture du fichier ZIP..."
    
    # Créer un fichier temporaire pour le traitement
    local temp_dir=$(mktemp -d)
    trap "rm -rf '$temp_dir'" EXIT
    
    # Extraire et traiter les fichiers
    [ $quiet -eq 0 ] && print_info "Extraction des données..."
    
    unzip -q -o "$zip_file" -d "$temp_dir" 2>/dev/null || true
    
    # Vérifier les fichiers extraits
    local watchlist="$temp_dir/watchlist.csv"
    local ratings="$temp_dir/ratings.csv"
    local likes="$temp_dir/likes/films.csv"
    
    # Créer des fichiers vides si non présents
    [ ! -f "$watchlist" ] && echo "Date,Name,Year,Letterboxd URI" > "$watchlist"
    [ ! -f "$ratings" ] && echo "Date,Name,Year,Letterboxd URI,Rating" > "$ratings"
    [ ! -f "$likes" ] && mkdir -p "$temp_dir/likes" && echo "Date,Name,Year,Letterboxd URI" > "$likes"
    
    [ $quiet -eq 0 ] && print_info "Fichiers trouvés:"
    [ $quiet -eq 0 ] && [ -f "$watchlist" ] && [ $(wc -l < "$watchlist") -gt 1 ] && print_info "  • watchlist.csv: $(($(wc -l < "$watchlist") - 1)) films"
    [ $quiet -eq 0 ] && [ -f "$ratings" ] && [ $(wc -l < "$ratings") -gt 1 ] && print_info "  • ratings.csv: $(($(wc -l < "$ratings") - 1)) films"
    [ $quiet -eq 0 ] && [ -f "$likes" ] && [ $(wc -l < "$likes") -gt 1 ] && print_info "  • likes/films.csv: $(($(wc -l < "$likes") - 1)) films"
    
    # Conversion avec AWK
    [ $quiet -eq 0 ] && print_info "Fusion des données..."
    
    awk -v watchlist_file="$watchlist" -v ratings_file="$ratings" -v likes_file="$likes" '
BEGIN {
    FS = ","
    OFS = ","
    
    # Traiter watchlist
    while ((getline line < watchlist_file) > 0) {
        if (NR_watch == 0) { NR_watch++; continue }
        process_line(line, "watchlist")
    }
    close(watchlist_file)
    NR_watch = 0
    
    # Traiter ratings
    while ((getline line < ratings_file) > 0) {
        if (NR_rate == 0) { NR_rate++; continue }
        process_line(line, "ratings")
    }
    close(ratings_file)
    NR_rate = 0
    
    # Traiter likes
    while ((getline line < likes_file) > 0) {
        if (NR_like == 0) { NR_like++; continue }
        process_line(line, "likes")
    }
    close(likes_file)
}

function clean(str) {
    gsub(/^[[:space:]]*"?|"?[[:space:]]*$/, "", str)
    gsub(/\r$/, "", str)
    return str
}

function parse_csv_line(line, fields,    in_quotes, field, char, i, n) {
    n = 0
    field = ""
    in_quotes = 0
    
    for (i = 1; i <= length(line); i++) {
        char = substr(line, i, 1)
        
        if (char == "\"") {
            in_quotes = !in_quotes
        } else if (char == "," && !in_quotes) {
            fields[++n] = field
            field = ""
        } else {
            field = field char
        }
    }
    fields[++n] = field
    return n
}

function process_line(line, type,    n, fields, name, year, key, rating_raw, rating) {
    n = parse_csv_line(line, fields)
    
    if (n < 3) return
    
    if (type == "watchlist") {
        name = clean(fields[2])
        year = clean(fields[3])
        
        if (name == "" || year == "") return
        key = name "|" year
        
        if (!(key in films)) {
            films[key] = name "|" year "||true|false|false"
        }
    }
    else if (type == "ratings") {
        name = clean(fields[2])
        year = clean(fields[3])
        rating_raw = clean(fields[5])
        
        if (name == "" || year == "") return
        key = name "|" year
        rating = int(rating_raw * 2)
        
        films[key] = name "|" year "|" rating "|false|false|true"
    }
    else if (type == "likes") {
        name = clean(fields[2])
        year = clean(fields[3])
        
        if (name == "" || year == "") return
        key = name "|" year
        
        if (key in films) {
            split(films[key], parts, "|")
            parts[5] = "true"
            films[key] = parts[1] "|" parts[2] "|" parts[3] "|" parts[4] "|" parts[5] "|" parts[6]
        } else {
            films[key] = name "|" year "||false|true|true"
        }
    }
}

END {
    # Header CSV SensCritique
    print "universe,title,release_date,rating,is_wishlisted,is_recommended,is_done"
    
    # Tri manuel des clés
    n = 0
    for (key in films) {
        sorted_keys[++n] = key
    }
    
    # Tri par insertion simple
    for (i = 2; i <= n; i++) {
        temp_key = sorted_keys[i]
        j = i - 1
        while (j >= 1 && sorted_keys[j] > temp_key) {
            sorted_keys[j + 1] = sorted_keys[j]
            j--
        }
        sorted_keys[j + 1] = temp_key
    }
    
    # Génération du CSV
    for (i = 1; i <= n; i++) {
        key = sorted_keys[i]
        split(films[key], parts, "|")
        
        title = parts[1]
        year = parts[2]
        rating = parts[3]
        wishlisted = parts[4]
        recommended = parts[5]
        done = parts[6]
        
        gsub(/"/, "\"\"", title)
        if (title ~ /[,"]/) {
            title = "\"" title "\""
        }
        
        print "movie," title "," year "," rating "," wishlisted "," recommended "," done
    }
}
' /dev/null > "$output_csv"
    
    local count=$(tail -n +2 "$output_csv" 2>/dev/null | wc -l | tr -d ' ')
    
    if [ $quiet -eq 0 ]; then
        echo ""
        print_success "Conversion terminée!"
        print_info "Fichier créé: $output_csv"
        print_info "Nombre de films: $count"
    fi
    
    return 0
}

# Mode interactif
interactive_mode() {
    while true; do
        show_menu
        read -p "Votre choix [1-3]: " choice
        echo ""
        
        case $choice in
            1)
                read -p "Chemin du fichier ZIP Letterboxd: " zip_file
                
                if [ -z "$zip_file" ]; then
                    print_error "Chemin vide"
                    read -p "Appuyez sur Entrée pour continuer..."
                    continue
                fi
                
                if ! validate_zip "$zip_file"; then
                    read -p "Appuyez sur Entrée pour continuer..."
                    continue
                fi
                
                read -p "Nom du fichier CSV de sortie [senscritique.csv]: " output_csv
                output_csv=${output_csv:-senscritique.csv}
                
                echo ""
                if convert_zip_to_csv "$zip_file" "$output_csv" 0; then
                    echo ""
                    print_success "Conversion réussie!"
                else
                    echo ""
                    print_error "La conversion a échoué"
                fi
                
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            2)
                show_help
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            3)
                echo "Au revoir!"
                exit 0
                ;;
            *)
                print_error "Choix invalide"
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
        esac
    done
}

# Point d'entrée principal
main() {
    local quiet=0
    
    # Parsing des arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                echo "Version $VERSION"
                exit 0
                ;;
            -q|--quiet)
                quiet=1
                shift
                ;;
            *)
                break
                ;;
        esac
    done
    
    # Vérifier les dépendances
    if ! check_dependencies; then
        exit 1
    fi
    
    # Mode ligne de commande
    if [ $# -eq 2 ]; then
        zip_file="$1"
        output_csv="$2"
        
        if ! validate_zip "$zip_file"; then
            exit 1
        fi
        
        if convert_zip_to_csv "$zip_file" "$output_csv" $quiet; then
            exit 0
        else
            exit 1
        fi
    elif [ $# -eq 0 ]; then
        # Mode interactif
        interactive_mode
    else
        print_error "Nombre d'arguments incorrect"
        echo ""
        show_help
        exit 1
    fi
}

# Lancement
main "$@"