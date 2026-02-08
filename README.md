# Better Places
Seiji E.

This project will attempt to investigate, prototype out, and evaluate an algorithm for better positioning
"places" pins in the overture maps dataset.

## To fetch source data:
### Overture Maps Data
```bash
data/tools/fetch_omf_data.d -p all
```
### Dependencies
* https://dlang.org
  * (install from there or use `ldc` aka `ldc2`: https://github.com/ldc-developers/ldc)
  * you need `rdmd` (`apt install <dmd | ldc>` / `brew install <dmd | ldc>` should suffice, probably)
