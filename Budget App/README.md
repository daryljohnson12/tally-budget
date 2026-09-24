# Tally Budget

A phone-friendly spending tracker. Log what you spend, see totals by day, week or month, and set a monthly budget for each category.

## Files
- `index.html` – the whole app
- `manifest.json`, `sw.js`, `icon-*.png` – let it install to your home screen and work offline

## Put it on your phone
The app needs to be served over HTTPS for "Add to Home Screen" to work. The easiest free option:

1. Go to https://app.netlify.com/drop and drag this whole folder onto the page.
2. Open the link it gives you on your phone.
3. iPhone: tap Share → **Add to Home Screen**. Android: tap ⋮ → **Install app**.

(GitHub Pages works too if you'd rather keep it in a repo.)

## Your data
Expenses are saved on the phone itself (browser storage). They aren't uploaded anywhere. Use **Data → Copy expenses as CSV** to back them up.
