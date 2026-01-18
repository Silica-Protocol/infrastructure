#!/usr/bin/env python3

import argparse
import json
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Tuple

# Default Docker Hub image for Silica nodes
DEFAULT_IMAGE = "silicaprotocol/silica-node"
DEFAULT_TAG = "testnet-latest"


@dataclass(frozen=True)
class Node:
    name: str
    public_ip: str


def run(cmd: List[str], cwd: Path | None = None) -> str:
    result = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"Command failed ({result.returncode}): {' '.join(cmd)}\n{result.stderr.strip()}"
        )
    return result.stdout


def tofu_outputs(module_dir: Path) -> Dict[str, object]:
    out = run(["tofu", "output", "-json"], cwd=module_dir)
    data = json.loads(out)
    # OpenTofu outputs JSON as {output_name: {"value": ...}}
    return {k: v.get("value") for k, v in data.items()}


def load_nodes(module_dir: Path) -> List[Node]:
    outputs = tofu_outputs(module_dir)
    validators = outputs.get("oci_validators")
    if not isinstance(validators, dict) or not validators:
        raise RuntimeError("No oci_validators output found. Did you run `tofu apply`?")

    nodes: List[Node] = []
    for name, info in validators.items():
        if not isinstance(info, dict):
            continue
        public_ip = info.get("public_ip")
        if not isinstance(public_ip, str) or not public_ip:
            continue
        nodes.append(Node(name=name, public_ip=public_ip))

    nodes.sort(key=lambda n: n.name)
    if not nodes:
        raise RuntimeError("No nodes with public_ip found in oci_validators output")
    return nodes


def ssh_args(user: str, extra: List[str] | None = None) -> List[str]:
    base = [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=accept-new",
        "-o",
        "ConnectTimeout=10",
    ]
    if extra:
        base.extend(extra)
    return base + [f"{user}@"]


def ssh_run(user: str, host: str, remote_cmd: str) -> str:
    cmd = [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=accept-new",
        "-o",
        "ConnectTimeout=10",
        f"{user}@{host}",
        remote_cmd,
    ]
    return run(cmd)


def scp_put(user: str, host: str, local_path: Path, remote_path: str) -> None:
    if not local_path.exists():
        raise RuntimeError(f"Local file not found: {local_path}")
    cmd = [
        "scp",
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=accept-new",
        "-o",
        "ConnectTimeout=10",
        str(local_path),
        f"{user}@{host}:{remote_path}",
    ]
    run(cmd)


def ssh_run_stdin(user: str, host: str, remote_cmd: str, stdin_data: str) -> str:
    cmd = [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=accept-new",
        "-o",
        "ConnectTimeout=10",
        f"{user}@{host}",
        remote_cmd,
    ]
    result = subprocess.run(
        cmd,
        input=stdin_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"Command failed ({result.returncode}): ssh {user}@{host} {remote_cmd}\n{result.stderr.strip()}"
        )
    return result.stdout


def cmd_list(nodes: List[Node]) -> None:
    for n in nodes:
        print(f"{n.name}\t{n.public_ip}")


def cmd_status(nodes: List[Node], user: str) -> None:
    for n in nodes:
        try:
            out = ssh_run(user, n.public_ip, "sudo systemctl is-active silica || true")
            state = out.strip() or "unknown"
        except Exception as e:
            state = f"error: {e}"
        print(f"{n.name}\t{n.public_ip}\t{state}")


def cmd_start(nodes: List[Node], user: str) -> None:
    for n in nodes:
        print(f"==> starting {n.name} ({n.public_ip})")
        ssh_run(user, n.public_ip, "sudo systemctl restart silica && sudo systemctl --no-pager status silica | head -n 20")


def cmd_bootstrap(nodes: List[Node], user: str) -> None:
        remote = r"""
set -euo pipefail

sudo apt-get update
sudo apt-get install -y docker.io docker-compose openssl

sudo systemctl enable --now docker

if [ -f /etc/systemd/system/silica.service ]; then
    sudo sed -i 's#/usr/bin/docker compose#/usr/bin/docker-compose#g' /etc/systemd/system/silica.service || true
    sudo sed -i 's/^Requires=docker\.service$/Wants=docker.service/' /etc/systemd/system/silica.service || true
    sudo sed -i 's/^Requires=docker\.service$/Wants=docker.service/' /etc/systemd/system/silica.service || true
fi

if [ -f /opt/silica/docker-compose.yml ]; then
    if ! grep -q '^version:' /opt/silica/docker-compose.yml; then
        sudo sed -i '1i version: "3.8"\n' /opt/silica/docker-compose.yml
    fi
fi

sudo systemctl daemon-reload
sudo systemctl enable silica || true
sudo systemctl restart silica || true
sudo systemctl --no-pager status silica | head -n 30 || true
"""

        for n in nodes:
                print(f"==> bootstrapping {n.name} ({n.public_ip})")
                ssh_run(user, n.public_ip, remote)


def cmd_logs(nodes: List[Node], user: str, node: str) -> None:
    selected = next((n for n in nodes if n.name == node), None)
    if selected is None:
        raise RuntimeError(f"Unknown node '{node}'. Use `list` to see names.")
    # Streaming logs: prefer docker-compose logs (more robust than assuming a container exists).
    # If docker-compose isn't available or the service isn't running yet, fall back to docker logs.
    primary = "cd /opt/silica && sudo docker-compose logs -f --tail=200 validator"
    fallback = "sudo docker logs -f silica-validator"
    remote_cmd = f"{primary} || ({fallback})"

    subprocess.run(
        [
            "ssh",
            "-o",
            "StrictHostKeyChecking=accept-new",
            f"{user}@{selected.public_ip}",
            remote_cmd,
        ],
        check=False,
    )


def cmd_push_consensus_key(nodes: List[Node], user: str, keys_dir: Path) -> None:
    for n in nodes:
        src = keys_dir / n.name / "consensus_keypair.json"
        print(f"==> pushing {src} -> {n.name} ({n.public_ip})")
        ssh_run(user, n.public_ip, "sudo mkdir -p /opt/silica/data/keys && sudo chown -R silica:silica /opt/silica/data")
        # copy to user home then move with sudo to avoid permission issues
        tmp_remote = f"/home/{user}/consensus_keypair.json"
        scp_put(user, n.public_ip, src, tmp_remote)
        ssh_run(
            user,
            n.public_ip,
            "sudo mv /home/" + user + "/consensus_keypair.json /opt/silica/data/keys/consensus_keypair.json && sudo chown silica:silica /opt/silica/data/keys/consensus_keypair.json && sudo systemctl restart silica",
        )


def cmd_ghcr_login(nodes: List[Node], user: str) -> None:
    ghcr_user = os.environ.get("GHCR_USERNAME")
    ghcr_token = os.environ.get("GHCR_TOKEN")
    if not ghcr_user or not ghcr_token:
        raise RuntimeError(
            "Missing GHCR credentials. Set GHCR_USERNAME and GHCR_TOKEN in your shell. "
            "Use a read-only token (at least read:packages)."
        )

    for n in nodes:
        print(f"==> logging in to ghcr.io on {n.name} ({n.public_ip})")
        ssh_run_stdin(
            user,
            n.public_ip,
            f"sudo docker login ghcr.io -u {ghcr_user} --password-stdin",
            ghcr_token + "\n",
        )
        ssh_run(user, n.public_ip, "sudo systemctl restart silica || true")


def cmd_set_image(nodes: List[Node], user: str, image: str) -> None:
    if not image.strip():
        raise RuntimeError("image must be a non-empty string")

    for n in nodes:
        print(f"==> setting image on {n.name} ({n.public_ip})")
        # Use sed with # delimiter to avoid issues with / in image names
        escaped_image = image.replace("/", "\\/")
        ssh_run(
            user,
            n.public_ip,
            f"sudo sed -i 's|^\\(\\s*image:\\s*\\).*|\\1{image}|' /opt/silica/docker-compose.yml",
        )
        ssh_run(user, n.public_ip, f"sudo docker pull {image}")
        ssh_run(user, n.public_ip, "sudo systemctl restart silica")


def _validator_index_from_name(node_name: str) -> int:
    """Extract validator index from node name like 'validator-0'."""
    parts = node_name.split("-")
    if len(parts) < 2:
        raise RuntimeError(f"Cannot parse validator index from node name: {node_name}")
    try:
        return int(parts[-1])
    except ValueError as e:
        raise RuntimeError(f"Cannot parse validator index from node name: {node_name}") from e


def cmd_push_genesis(nodes: List[Node], user: str, genesis_file: Path) -> None:
    if not genesis_file.exists():
        raise RuntimeError(f"Genesis file not found: {genesis_file}")

    for n in nodes:
        print(f"==> pushing genesis -> {n.name} ({n.public_ip})")
        ssh_run(user, n.public_ip, "sudo mkdir -p /opt/silica/data/storage && sudo chown -R 1000:1000 /opt/silica/data")
        tmp_remote = f"/home/{user}/genesis.json"
        scp_put(user, n.public_ip, genesis_file, tmp_remote)
        ssh_run(
            user,
            n.public_ip,
            "sudo mv /home/" + user + "/genesis.json /opt/silica/data/storage/genesis.json && sudo chown 1000:1000 /opt/silica/data/storage/genesis.json",
        )
        ssh_run(user, n.public_ip, "sudo systemctl restart silica")


def cmd_set_bootstrap_peers(nodes: List[Node], user: str, port: int) -> None:
    if port <= 0 or port > 65535:
        raise RuntimeError("port must be in 1..65535")

    # Build a multiaddr list for each node based on current tofu outputs
    node_addrs = {n.name: f"/ip4/{n.public_ip}/udp/{port}/quic-v1" for n in nodes}

    for n in nodes:
        peers = [addr for name, addr in node_addrs.items() if name != n.name]
        print(f"==> configuring bootstrap peers for {n.name} ({n.public_ip})")
        peers_py = "[" + ", ".join(repr(p) for p in peers) + "]"
        remote = f"""
set -euo pipefail

cfg=/opt/silica/config/validator.toml
sudo test -f "$cfg"

python3 - <<'PY'
import json
import re

cfg = "/opt/silica/config/validator.toml"
peers = {peers_py}

with open(cfg, "r", encoding="utf-8") as f:
    text = f.read()

pattern = re.compile(r"(?m)^(?P<indent>\\s*)bootstrap_peers\\s*=\\s*\\[[^\\]]*\\]\\s*$")

def repl(m):
    indent = m.group("indent")
    peers_toml = ", ".join(json.dumps(x) for x in peers)
    return indent + "bootstrap_peers = [" + peers_toml + "]"

new_text, n = pattern.subn(repl, text)
if n == 0:
    raise SystemExit("bootstrap_peers line not found in validator.toml")

tmp = "/tmp/validator.toml"
with open(tmp, "w", encoding="utf-8") as f:
    f.write(new_text)
PY

sudo mv /tmp/validator.toml "$cfg"
sudo systemctl restart silica
"""
        ssh_run(user, n.public_ip, remote)


def cmd_reset_consensus_key(nodes: List[Node], user: str) -> None:
    for n in nodes:
        idx = _validator_index_from_name(n.name)
        print(f"==> resetting consensus key for {n.name} ({n.public_ip}) [index {idx}]")
        # Ensure SILICA_VALIDATOR_INDEX is set in docker-compose.yml so the node regenerates
        # deterministic genesis keys when the file is missing.
        remote = f"""
set -euo pipefail
cd /opt/silica

sudo test -f docker-compose.yml

# Ensure env vars exist in compose file (assumes default template indentation)
if ! sudo grep -q 'SILICA_NETWORK_MODE=' docker-compose.yml; then
    sudo sed -i '/- RUST_BACKTRACE=1/a            - SILICA_NETWORK_MODE=testnet' docker-compose.yml
fi

if sudo grep -q 'SILICA_VALIDATOR_INDEX=' docker-compose.yml; then
    sudo sed -i 's/^\(\s*-\s*SILICA_VALIDATOR_INDEX=\).*/\1{idx}/' docker-compose.yml
else
    # Insert index after network mode line if present, else after backtrace.
    if sudo grep -q 'SILICA_NETWORK_MODE=testnet' docker-compose.yml; then
        sudo sed -i '/SILICA_NETWORK_MODE=testnet/a            - SILICA_VALIDATOR_INDEX={idx}' docker-compose.yml
    else
        sudo sed -i '/- RUST_BACKTRACE=1/a            - SILICA_VALIDATOR_INDEX={idx}' docker-compose.yml
    fi
fi

# Remove the existing key so silica can regenerate deterministically
sudo rm -f /opt/silica/data/keys/consensus_keypair.json

sudo systemctl restart silica
"""
        ssh_run(user, n.public_ip, remote)


def cmd_update(nodes: List[Node], user: str, tag: str, force: bool) -> None:
    """Pull latest image and restart all nodes."""
    image = f"{DEFAULT_IMAGE}:{tag}"
    
    print(f"Updating nodes to image: {image}")
    print("=" * 60)
    
    for n in nodes:
        print(f"\n==> updating {n.name} ({n.public_ip})")
        
        # Update docker-compose.yml with new image using sed with | delimiter
        ssh_run(
            user,
            n.public_ip,
            f"sudo sed -i 's|^\\(\\s*image:\\s*\\).*|\\1{image}|' /opt/silica/docker-compose.yml",
        )
        
        # Pull new image
        print(f"    Pulling {image}...")
        ssh_run(user, n.public_ip, f"sudo docker pull {image}")
        
        # Restart service
        print(f"    Restarting silica service...")
        ssh_run(user, n.public_ip, "sudo systemctl restart silica")
        
        # Show brief status
        try:
            out = ssh_run(user, n.public_ip, "sudo systemctl is-active silica || true")
            status = out.strip() or "unknown"
            print(f"    Status: {status}")
        except Exception as e:
            print(f"    Status check failed: {e}")
    
    print("\n" + "=" * 60)
    print(f"Update complete. All nodes now running: {image}")
    print("\nTo check logs: ./silica_nodes.py logs validator-0")
    print("To check status: ./silica_nodes.py status")


def main() -> int:
    module_dir = Path(__file__).resolve().parents[1]

    parser = argparse.ArgumentParser(description="Manage OCI Silica nodes from OpenTofu outputs")
    parser.add_argument("--user", default="silica", help="SSH user (default: silica)")

    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list", help="List nodes and public IPs")
    sub.add_parser("status", help="Show systemd service status for each node")
    sub.add_parser("start", help="Restart service on each node")
    sub.add_parser("bootstrap", help="Install docker-compose and fix node service files")
    sub.add_parser("ghcr-login", help="Docker login to ghcr.io on each node (uses GHCR_USERNAME/GHCR_TOKEN env vars)")
    
    p_update = sub.add_parser("update", help=f"Pull latest image from Docker Hub and restart all nodes (default: {DEFAULT_IMAGE}:{DEFAULT_TAG})")
    p_update.add_argument("--tag", default=DEFAULT_TAG, help=f"Image tag to deploy (default: {DEFAULT_TAG})")
    p_update.add_argument("--force", action="store_true", help="Force pull even if image exists locally")
    
    p_set_image = sub.add_parser("set-image", help="Update /opt/silica/docker-compose.yml to use a new image, then pull + restart")
    p_set_image.add_argument("--image", required=True, help="Container image reference (e.g. ghcr.io/owner/repo:latest)")

    p_push_genesis = sub.add_parser("push-genesis", help="Copy a shared genesis.json to all nodes (stored at /opt/silica/data/storage/genesis.json) and restart")
    p_push_genesis.add_argument("--file", required=True, help="Path to genesis.json on your local machine")

    p_bootstrap = sub.add_parser("set-bootstrap-peers", help="Set network.bootstrap_peers in /opt/silica/config/validator.toml using current tofu public IPs, then restart")
    p_bootstrap.add_argument("--port", type=int, default=30300, help="UDP port for QUIC listen (default: 30300)")

    sub.add_parser("reset-consensus-key", help="Delete consensus_keypair.json on each node so it is regenerated deterministically using SILICA_VALIDATOR_INDEX, then restart")

    logs_p = sub.add_parser("logs", help="Tail docker logs for a single node")
    logs_p.add_argument("node", help="Node name (e.g., validator-0)")

    push_p = sub.add_parser("push-consensus-keys", help="Push consensus_keypair.json for each node")
    push_p.add_argument(
        "--keys-dir",
        default=str(module_dir / "keys"),
        help="Directory with per-node keys: <keys-dir>/<node>/consensus_keypair.json",
    )

    args = parser.parse_args()

    nodes = load_nodes(module_dir)

    if args.cmd == "list":
        cmd_list(nodes)
        return 0
    if args.cmd == "status":
        cmd_status(nodes, args.user)
        return 0
    if args.cmd == "start":
        cmd_start(nodes, args.user)
        return 0
    if args.cmd == "bootstrap":
        cmd_bootstrap(nodes, args.user)
        return 0
    if args.cmd == "logs":
        cmd_logs(nodes, args.user, args.node)
        return 0
    if args.cmd == "push-consensus-keys":
        cmd_push_consensus_key(nodes, args.user, Path(args.keys_dir))
        return 0
    if args.cmd == "ghcr-login":
        cmd_ghcr_login(nodes, args.user)
        return 0
    if args.cmd == "update":
        cmd_update(nodes, args.user, args.tag, args.force)
        return 0
    if args.cmd == "set-image":
        cmd_set_image(nodes, args.user, args.image)
        return 0

    if args.cmd == "push-genesis":
        cmd_push_genesis(nodes, args.user, Path(args.file))
        return 0

    if args.cmd == "set-bootstrap-peers":
        cmd_set_bootstrap_peers(nodes, args.user, args.port)
        return 0

    if args.cmd == "reset-consensus-key":
        cmd_reset_consensus_key(nodes, args.user)
        return 0

    raise RuntimeError("Unhandled command")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
    except Exception as e:
        print(str(e), file=sys.stderr)
        raise SystemExit(1)
