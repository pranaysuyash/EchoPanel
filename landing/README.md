# EchoPanel Landing Page

Static landing page with a custom waitlist form wired to Google Sheets via Apps Script.

## Files
- `landing/index.html`
- `landing/styles.css`
- `landing/app.js`
- `landing/apps_script.gs`

## Customize copy
Edit `landing/index.html` to update the headline, subhead, and CTA text.

## Design system tokens
Tokens are defined in `landing/styles.css` under `:root`.
- Colors: `--bg`, `--panel`, `--accent`, `--muted`
- Radii: `--radius-lg`, `--radius-md`, `--radius-sm`
- Shadow: `--shadow`

## Google Sheets waitlist setup
1) Create a Google Sheet named `EchoPanel Waitlist`.
2) Extensions -> Apps Script.
3) Paste `landing/apps_script.gs` into the script editor.
4) Deploy -> New deployment -> Web app.
   - Execute as: Me
   - Who has access: Anyone
5) Copy the deployment URL and update `WAITLIST_ENDPOINT` in `landing/app.js`.

## Cloudflare Pages deploy
1) Push the repo to GitHub.
2) Create a new Cloudflare Pages project.
3) Set:
   - Build command: (leave empty)
   - Build output directory: `landing`
4) Deploy.

## S3 deploy
1) Create an S3 bucket and enable static website hosting.
2) Upload all files from `landing/` to the bucket root.
3) Set the index document to `index.html`.
4) Configure public read access or use CloudFront.

## Local preview
```sh
python -m http.server 8080 --directory landing
```
