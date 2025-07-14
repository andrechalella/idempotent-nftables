# idempotent-nftables

`nftables` is famous for being a bit clumsy to script and automate, especially with regards to idempotency: run twice, you get duplicated rules. Sometimes, we want to experiment and iterate quickly with nftables custom rules.

An easy way to achieve idempotency is:
- Always use private tables, with unique names (e.g no `ip filter` table);
- Then you can just purge the entire table before applying the updated set of rules.

I made a simple systemd service to automate this process. With it, you can modify your rules in text files and apply them cleanly by triggering a reload of the service. The old rules are always purged.

## How to use

1. Drop an `.nft` file in `/etc/idempotent_nftables` like the one in the example directory (pasted below):

```
#!/usr/sbin/nft -f

table ip restrict_docker0 {
        chain filter_forward {
                type filter hook forward priority -10; policy accept;
                iifname docker0 ct state new drop
        }
}
```

2. Now run `systemctl start idempotent-nftables` (or `reload`, it's the same)
3. Find that it was loaded with `nft list ruleset`
4. Modify that file, delete it or don't do anything at all
5. Run systemctl again (`reload` would be more semantic this time, but again it's the same)
6. Check the ruleset again and find that there are no old or duplicated rules there

### Caveat

**Always use private, unique names for your tables or you'll delete unintended rules.**

Yes, it's the first rule I stated in the beginning of this document.

## Installation

Tested in Debian.

1. Download both files from the `/src` directory (`idempotent_nftables.sh` and `idempotent-nftables.service`)
2. As root, run the commands in the same directory as the downloaded files:

```
mkdir /etc/idempotent_nftables
mv idempotent_nftables.sh /etc/idempotent_nftables
chmod a+x /etc/idempotent_nftables/idempotent_nftables.sh
mv idempotent-nftables.service /etc/systemd/system
systemctl enable idempotent-nftables
```

The `systemctl enable` line makes the service run automatically at boot, thus applying your custom rules.
