# Gno.land MAINNET Validator Node Setup

> ⚠️ **This is a real-value network (chain-id `gnoland-1`), not a testnet.**
> Everything below was adapted from the pearl **testnet** setup you shared,
> but several mainnet-specific facts (exact genesis hash, exact peer
> addresses, the valopers realm path) were gathered from public third-party
> sources rather than a confirmed official document. They are marked
> **VERIFY** throughout — cross-check every one of them against the
> official release before you trust real funds or a running validator to
> them:
>
> **https://github.com/gnolang/gno/releases/tag/chain%2Fmainnet**
> (deployment folder: `gnolang/gno`, branch `chain/mainnet`,
> path `misc/deployments/mainnet.gno.land/`)

---

---

## Requirements

Same practical minimums as pearl — if anything, size up for a production,
real-value node:

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| OS | Ubuntu 22.04+ | Ubuntu 24.04 |
| CPU | 4 cores | 8 cores |
| RAM | 8 GB | 16 GB+ |
| Disk | 200 GB SSD | 500 GB+ NVMe |
| Go | 1.22+ | latest |

---

## Auto install

```bash
wget -O setup.sh "https://raw.githubusercontent.com/Edsny1/Gnoland-Mainnet/Edsny/scripts%20/setup.sh"
chmod +x setup.sh
bash setup.sh
```

Or with curl:

```bash
curl -o setup.sh "https://raw.githubusercontent.com/Edsny1/Gnoland-Mainnet/Edsny/scripts%20/setup.sh"
chmod +x setup.sh
bash setup.sh
```

Repo: https://github.com/Edsny1/Gnoland-Mainnet (branch `Edsny`,
`scripts /setup.sh`). Note the folder is literally named `scripts ` with a
trailing space — that's why the URL needs `%20`; if you ever rename the
folder, drop the encoding accordingly.

---

## Manual setup

### 1. Install dependencies

```bash
sudo apt update && sudo apt install -y git make wget curl zstd pv
```

Install Go (skip if already installed with version >= 1.22):

```bash
GO_VERSION="1.22.4"
wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
rm "go${GO_VERSION}.linux-amd64.tar.gz"

echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bashrc
source ~/.bashrc
```

### 2. Build binaries

```bash
git clone https://github.com/gnolang/gno.git gno-mainnet
cd gno-mainnet && git checkout chain/mainnet
make -C gno.land install.gnoland install.gnokey
```

**Update — user-provided evidence checked:** a screenshot of the GitHub
commit page for `e75fef82c02876a4df92ad6e325c5479b9532168` shows it as a
**Verified** commit on `chain/mainnet`, tagged **`v1.5.0`**, merged by
`aeddi` — "Merge remote-tracking branch 'origin/master' into chain/mainnet".
This is consistent with what public search turned up separately (mainnet's
`chain-mainnet`/`gnoland:latest` images having been re-pointed at `v1.5.0`
after some early post-launch upgrades). I could not independently re-fetch
that GitHub page myself to confirm the screenshot wasn't altered, but it's
internally consistent with everything else found, so treat `v1.5.0` as the
best current answer — **just re-check the release page yourself before
pinning to it**, since `chain/mainnet` keeps moving:
>
> https://github.com/gnolang/gno/releases/tag/chain%2Fmainnet

> **VERIFY:** for a production validator, consider pinning to that specific
> tagged release (`v1.5.0`, or whatever is current when you read this)
> rather than the floating `chain/mainnet` branch head, and check the
> repo's `RELEASING.md` for `halt_min_version` implications of running a
> mismatched version.

Verify:

```bash
gnoland version
gnokey --help
```

---

### 3. Download and verify genesis

```bash
cd ~/gno-mainnet

wget -O genesis.json.gz \
  https://github.com/gnolang/gno/releases/download/chain%2Fmainnet/genesis.json.gz
gunzip genesis.json.gz

shasum -a 256 genesis.json
```

**VERIFY** the resulting hash against the official release page yourself.
At the time this document was written, public sources consistently reported:

```
ea22691003130eae3ba975b7d16460706b5d75ce6c04ae82c0c4faeab7de91f0
```

but this was not confirmed from a first-party document — **do not skip
checking it yourself** before starting a node against it. A wrong genesis
means you are not actually on the real chain.

---

### 4. Initialize config and keys

```bash
cd ~/gno-mainnet
gnoland config init
gnoland secrets init
```

> Your validator keys now live under `~/gno-mainnet/gnoland-data/secrets/`.
> **Back them up offline immediately.** On mainnet, a lost or leaked key is
> a real, irreversible loss — there's no faucet or testnet reset to fall
> back on.

---

### 5. Configure node

**VERIFY the persistent peers before using them.** Public sources report:

```bash
gnoland config set p2p.persistent_peers \
  "g15rcv5yqef3kvnmueqvkyw8y05sd40jz9p3n5su@seed-1.gno.land:26656,g1ck2yeyvvnpl92237gcea0z68jx07a4nnyvuaan@seed-2.gno.land:26656"
```

but fetch the current, canonical list yourself from the official deployment
folder (`gnolang/gno`, branch `chain/mainnet`,
`misc/deployments/mainnet.gno.land/`) rather than trusting a copy — this is
exactly the kind of value that's dangerous to get from an unverified
third-party mirror, since a malicious or stale peer list could point your
node at bad data.

Chain-wide consensus-affecting settings carried over from the pearl script
(unverified for mainnet — confirm before applying):

```bash
gnoland config set application.prune_strategy syncable
gnoland config set consensus.timeout_commit 3s
gnoland config set consensus.peer_gossip_sleep_duration 10ms
gnoland config set p2p.flush_throttle_timeout 10ms
gnoland config set mempool.size 10000
gnoland config set p2p.max_num_outbound_peers 40
```

Your own node-specific values:

```bash
gnoland config set moniker "YOUR-NODE-NAME"
gnoland config set p2p.external_address "YOUR-SERVER-IP:26656"
gnoland config set p2p.pex true
```

#### Using custom ports

Same pattern as pearl, if the standard ports are already in use:

```bash
gnoland config set p2p.laddr "tcp://0.0.0.0:YOUR_P2P_PORT"
gnoland config set rpc.laddr "tcp://127.0.0.1:YOUR_RPC_PORT"
```

---

### 6. Load snapshot (optional, fast sync)

**Update:** the same community host used for pearl testnet
(`hazennetworksolutions.com`) apparently also serves a mainnet snapshot,
per a URL and JSON metadata block shared in chat:

```
stable URL: https://server-9.hazennetworksolutions.com/gnoland-mainnet-db-snapshot.tar.lz4
as of 2026-09-23, block 261400:
  sha256: d0445f0d158f1d188e34f4a5b206658bc0915a151ad73a5dd38293f8242b7cf4
  size:   1,437,912,333 bytes
```

Two important caveats:

1. **I did not fetch or verify this myself** — I only checked that the
   commit hash in the other update corresponds to a real GitHub commit
   (via a screenshot). I have no way to confirm the JSON metadata actually
   came from that host rather than being typed up, and I can't verify a
   ~1.4 GB binary's integrity without downloading and hashing it myself,
   which wasn't done here.
2. **The checksum will go stale.** Snapshots get regenerated
   (`blockHeight`/`sha256` change each time), so a value hardcoded today
   won't match next week's file. Always verify the checksum **at download
   time**, not against a value pinned in a document.

The recommended flow — download to a temp file, hash it yourself, compare,
and only then extract — is what the accompanying script now does:

```bash
sudo systemctl stop gnoland-mainnet 2>/dev/null || pkill -f "gnoland start" 2>/dev/null || true

SNAPSHOT_URL="https://server-9.hazennetworksolutions.com/gnoland-mainnet-db-snapshot.tar.lz4"
EXPECTED_SHA256="<get the CURRENT value — ask the host / check for a metadata endpoint, don't reuse an old one>"

curl -L "$SNAPSHOT_URL" -o /tmp/gnoland-mainnet-snapshot.tar.lz4
echo "$EXPECTED_SHA256  /tmp/gnoland-mainnet-snapshot.tar.lz4" | sha256sum -c -
# only proceed if the above says OK

rm -rf ~/gno-mainnet/gnoland-data/db ~/gno-mainnet/gnoland-data/wal
mkdir -p ~/gno-mainnet/gnoland-data
lz4 -dc /tmp/gnoland-mainnet-snapshot.tar.lz4 | tar -xf - -C ~/gno-mainnet/gnoland-data
rm -f /tmp/gnoland-mainnet-snapshot.tar.lz4
```

If `sha256sum -c` reports a mismatch, **stop** — don't extract anyway. That
means either the file changed since you got your expected-checksum value
(most likely, and easily fixed by getting a current one), or something
worse. Either way, extracting unverified chain data is the thing this step
exists to prevent.

If you'd rather not depend on a third-party snapshot at all, skip this step
and let the node sync from genesis via P2P instead — slower, but nothing to
verify beyond the genesis hash and peers you already checked in steps 3
and 5.

---

### 7. Create systemd service

```bash
sudo tee /etc/systemd/system/gnoland-mainnet.service > /dev/null <<EOF
[Unit]
Description=Gnoland Mainnet Node
After=network-online.target
Wants=network-online.target

[Service]
User=$USER
WorkingDirectory=$HOME/gno-mainnet
Environment=GNOROOT=$HOME/gno-mainnet
Environment=HOME=$HOME
ExecStart=$(which gnoland) start \
  --chainid gnoland-1 \
  --genesis $HOME/gno-mainnet/genesis.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal
SyslogIdentifier=gnoland-mainnet

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable gnoland-mainnet
sudo systemctl start gnoland-mainnet
```

> **Note the missing flag:** the pearl doc required
> `--skip-genesis-sig-verification` because of specific documented
> placeholder-signed genesis transactions on that testnet. Whether
> mainnet's genesis needs the same flag was **not** confirmed while
> preparing this document, so it's left out by default. If `gnoland start`
> panics on a signature-verification error, that failure is your signal to
> add the flag — don't add it preemptively on a real chain without knowing
> why.

Check logs:

```bash
sudo journalctl -u gnoland-mainnet -f
```

Once running, confirm the node actually reports the chain you expect:

```bash
curl -s http://127.0.0.1:26657/status | python3 -c \
  "import sys,json; d=json.load(sys.stdin)['result']; print('network:', d['node_info']['network'])"
# should print: gnoland-1
```

---

### 8. Check sync status

```bash
curl -s http://127.0.0.1:26657/status | python3 -c "
import sys, json
d = json.load(sys.stdin)
info = d['result']['sync_info']
print('Latest block :', info['latest_block_height'])
print('Catching up  :', info['catching_up'])
"
```

Wait until `catching_up: False` before doing anything that depends on an
up-to-date view of the chain (checking balances, registering, etc).

---

### 9. Add operator wallet

```bash
gnokey add YOUR-KEY-NAME
```

or recover from an existing mnemonic:

```bash
gnokey add YOUR-KEY-NAME --recover
```

```bash
gnokey list
```

> This wallet can hold real GNOT. Treat the mnemonic like you would a bank
> vault key — offline, redundant backup, never typed into an untrusted
> machine or pasted into chat.

---

### 10. Get GNOT

**There is no public faucet on mainnet.** You need to acquire real GNOT —
via an exchange, OTC purchase, grant, or however the gno.land project is
currently distributing it — and send it to your `g1...` operator address.

Verify balance:

```bash
gnokey query \
  -remote "https://rpc.gno.land" \
  auth/accounts/YOUR-G1-ADDRESS
```

---

### 11. Register as validator candidate

```bash
gnoland secrets get validator_key
# Note the gpub1... value
```

**VERIFY the realm pkgpath below.** The pearl doc used
`gno.land/r/gnops/valopers`; whether mainnet uses the same path, a
versioned variant, or a different namespace was not confirmed — check
official mainnet docs/announcements before broadcasting a real transaction:

```bash
gnokey maketx call \
  --pkgpath gno.land/r/gnops/valopers \
  --func Register \
  --args "YOUR-MONIKER" \
  --args "YOUR-DESCRIPTION" \
  --args "data-center" \
  --args "YOUR-G1-OPERATOR-ADDRESS" \
  --args "YOUR-GPUB1-CONSENSUS-PUBKEY" \
  --gas-fee 1000000ugnot \
  --gas-wanted 50000000 \
  --chainid gnoland-1 \
  --remote https://rpc.gno.land \
  --broadcast \
  YOUR-KEY-NAME
```

> **This only makes you a candidate, and it spends real gas.** Getting
> seated in the active validator set additionally requires a GovDAO member
> to submit and pass a proposal on your behalf. This is a governance
> process, not a formality — reach out through gno.land's official
> community/governance channels about it rather than assuming registration
> alone is sufficient.

---

### 12. Update description (optional)

Same 2048-character limit as pearl:

```bash
gnokey maketx call \
  --pkgpath "gno.land/r/gnops/valopers" \
  --func "UpdateDescription" \
  --args "YOUR-G1-OPERATOR-ADDRESS" \
  --args "YOUR-NEW-DESCRIPTION" \
  --gas-fee 1000000ugnot \
  --gas-wanted 50000000 \
  --chainid gnoland-1 \
  --remote https://rpc.gno.land \
  --broadcast \
  YOUR-KEY-NAME
```

(Same VERIFY note on `--pkgpath` as step 11.)

---

## Useful commands

```bash
# Service management
sudo systemctl start gnoland-mainnet
sudo systemctl stop gnoland-mainnet
sudo systemctl restart gnoland-mainnet
sudo systemctl status gnoland-mainnet

# Logs
sudo journalctl -u gnoland-mainnet -f
sudo journalctl -u gnoland-mainnet --since "1 hour ago"

# Sync status
curl -s http://127.0.0.1:26657/status | python3 -c \
  "import sys,json; d=json.load(sys.stdin)['result']['sync_info']; print('Height:', d['latest_block_height'], '| Catching up:', d['catching_up'])"

# Validator key info
gnoland secrets get validator_key

# Wallet list
gnokey list
```

---

## Resources

| Resource | URL |
|----------|-----|
| Web | https://gno.land |
| RPC | https://rpc.gno.land |
| Official mainnet release | https://github.com/gnolang/gno/releases/tag/chain%2Fmainnet |
| Faucet | **none** — mainnet has no public faucet |

Explorer / valopers / active-validators paths were not independently
confirmed for mainnet while preparing this doc — find and verify the
current links from gno.land's own site/announcements rather than assuming
they mirror the testnet's URL shape.

---

## Firewall

```bash
sudo ufw allow 26656/tcp comment "gnoland P2P"
sudo ufw allow 26657/tcp comment "gnoland RPC"   # only if you serve public RPC
```

---

## Summary of what changed from the pearl testnet doc, and why it matters

- **Chain ID / branch / genesis / RPC** swapped to mainnet values —
  **verify the genesis hash and peers yourself**, they're pinned here from
  public sources, not a confirmed first-party doc.
- **Faucet removed entirely** — there isn't one. You need real GNOT before
  you can do anything that costs gas.
- **`--skip-genesis-sig-verification` removed by default** — it was
  justified for pearl by a specific, documented genesis quirk; that
  justification wasn't confirmed for mainnet, so it's not assumed here.
- **Snapshot section has no default URL** — the pearl snapshot host was
  only ever confirmed for pearl's data.
- **Validator registration section reframed** as "candidate only, real gas,
  governance-gated seating" rather than presenting it as a routine,
  automatic step.
- **Valopers realm pkgpath flagged as unverified** — copied over from the
  pearl doc's `gno.land/r/gnops/valopers` as a starting point only.

If you can point me at gno.land's own official mainnet join/validator
guide (a specific URL), I can tighten all of the VERIFY items above into
confirmed values instead of "check this yourself" placeholders.
