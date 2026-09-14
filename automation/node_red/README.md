# Node-RED WhatsApp Automation for Real Estate CRM

This flow provides zero-cost automated lead capture and document dispatch directly via WhatsApp using `whatsapp-web.js` emulation inside Node-RED.

## Prerequisites

1. Install Node-RED globally (or run inside Docker):
   ```bash
   npm install -g --unsafe-perm node-red
   ```
2. Install the WhatsApp Web integration node:
   ```bash
   cd ~/.node-red
   npm install node-red-contrib-whatsapp-web
   ```

## How to Import

1. Start Node-RED:
   ```bash
   node-red
   ```
2. Open `http://localhost:1880` in your browser.
3. Click the hamburger menu (top right) -> **Import**.
4. Paste the contents of `whatsapp_lead_flow.json` or select the file.
5. Click **Import** and then **Deploy**.
6. Scan the QR code shown in Node-RED debug tab to link your WhatsApp business number.

## Environment Variables
Ensure the following variables are defined in your `.env` or Node-RED settings:
- `SUPABASE_URL`: e.g. `https://your-project.supabase.co`
- `SUPABASE_ANON_KEY`: Supabase project anon key
- `API_OCR_BASE_URL`: e.g. `http://127.0.0.1:8000`
- `OCR_API_KEY`: Secret matching your Python OCR microservice
