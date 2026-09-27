# Domain lists

Drop plain text files here, one domain per line (comments `#`/`!` ok). Hosts
format (`0.0.0.0 domain`) is also accepted. These are git-ignored.

Suggested starting points (download yourself, review before use):
- Adult content: StevenBlack "porn" hosts, or a category list from a public
  blocklist project.
- Ads/tracking: StevenBlack base hosts, AdGuard, or Peter Lowe's list.

Example:
    curl -fsSL <blocklist-url> -o adult.txt
    sudo python3 ../build_blocklist.py --block adult.txt --allow allow.txt --reload
