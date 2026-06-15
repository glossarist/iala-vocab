# IALA Dictionary

[![Deploy](https://github.com/glossarist/iala-vocab/actions/workflows/deploy.yml/badge.svg)](https://github.com/glossarist/iala-vocab/actions/workflows/deploy.yml)

The International Association of Lighthouse Authorities (IALA) Dictionary is a comprehensive vocabulary resource for maritime navigation and lighthouse terminology. This site provides access to standardized definitions across multiple editions.

## Repository Structure

- `concepts/` — YAML files containing concept definitions
- `scripts/` — Ruby scripts for scraping and processing IALA data
- `public/` — Static assets (favicon, etc.)
- `site-config.yml` — Configuration for the concept browser
- `package.json` — Node.js dependencies and build scripts
- `Gemfile` — Ruby dependencies

## Building Locally

### Prerequisites

- Node.js 20 or later
- Ruby 3.0 or later
- npm or yarn

### Installation and Development

```bash
# Install Node.js dependencies
npm install

# Install Ruby dependencies
bundle install

# Generate concept data
npm run generate

# Start development server
npm run dev
```

The development server will be available at `http://localhost:5173`.

### Production Build

```bash
npm run build
```

## Configuration

The site is configured via `site-config.yml`, which specifies:

- `basePath` — Base URL path for deployment
- `localPath` — Local file path for concept data
- `title` — Site title and branding

## Dataset

The IALA Dictionary includes two main editions:

- **1970-89** — Early standardized definitions
- **2023** — Current edition with updated terminology

## Updating the Dataset

To update the vocabulary data:

1. Run the Ruby scraper scripts in `scripts/`:
   ```bash
   bundle exec ruby scripts/scrape_iala.rb
   ```

2. The scripts will fetch data from IALA sources and generate YAML concept files in `concepts/`

3. Regenerate the site:
   ```bash
   npm run generate
   npm run build
   ```

## License

This project is licensed under the CC BY 4.0 License. See LICENSE file for details.
