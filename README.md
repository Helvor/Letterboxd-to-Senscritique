# Letterboxd-to-Senscritique
Script to import letterboxd to senscritique made with [Claude AI](https://claude.ai/)
Don't hesitate to fork or whatever
## What the script do
Parse the format from letterboxd into the zip and get 3 files :
- ratings.csv
- likes/films.csv
- watchlist.csv
Then combined ratings and likes to marked it as "recommanded" on Senscritique if you've liked it on Letterboxd
Output in the format that Senscritique required (https://www.senscritique.com/l-edito/post/comment_importer_ses_notes_sur_senscritique)
---
# Steps
1. Export data from letterboxd on https://letterboxd.com/settings/data/
2. Run `./letterboxd_to_sc.sh letterboxd-<username>-<date>.zip output.csv`
3. (optionnal) Run checked script `./checked_exported.sh output.csv`
4. Import the file on https://www.senscritique.com/parametres/compte
5. Enjoy
