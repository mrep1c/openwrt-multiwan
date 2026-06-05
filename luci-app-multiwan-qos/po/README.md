# MultiWAN QoS Translations

This directory contains translations for the MultiWAN QoS LuCI application.

## Contributing Translations

1. Copy templates/multiwan_qos.pot to xx.po (where xx is your language code)
2. Translate the strings in your xx.po file
3. Submit a pull request

## Available Languages
- English (default)
- German (de.po) (test)

## Creating/Updating Translations
Use these commands to update translations:

```bash
# Update .pot template
./scripts/i18n-scan.pl htdocs > po/templates/multiwan_qos.pot

# Update existing .po files
./scripts/i18n-update.pl po/templates/multiwan_qos.pot po/*.po
