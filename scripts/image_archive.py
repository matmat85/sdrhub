import argparse
import hashlib
import json
import re
import tarfile


def image_ids(path):
    with tarfile.open(path, "r:*") as archive:
        def read_json(name):
            member = archive.getmember(name)
            if not member.isfile() or member.size > 4 * 1024 * 1024:
                raise ValueError(f"Invalid image metadata member: {name}")
            with archive.extractfile(member) as file:
                content = file.read()
            return json.loads(content), "sha256:" + hashlib.sha256(content).hexdigest()

        manifest, _ = read_json("manifest.json")
        if len(manifest) != 1 or manifest[0].get("RepoTags") != ["loft/sdr-hub:local"]:
            raise ValueError("Expected exactly one loft/sdr-hub:local image")
        config, config_id = read_json(manifest[0]["Config"])
        if config.get("os") != "linux" or config.get("architecture") != "amd64":
            raise ValueError("Expected a Linux amd64 hub image")
        identities = {config_id}
        if "index.json" in archive.getnames():
            index, _ = read_json("index.json")
            visiting = set()

            def matches_config(descriptor):
                digest = descriptor["digest"]
                if not re.fullmatch(r"sha256:[a-f0-9]{64}", digest) or digest in visiting:
                    raise ValueError("Invalid or cyclic OCI image descriptor")
                visiting.add(digest)
                document, actual = read_json("blobs/sha256/" + digest[7:])
                if actual != digest:
                    raise ValueError("OCI image descriptor checksum mismatch")
                if "manifests" in document:
                    matching = [matches_config(child) for child in document["manifests"]]
                    matches = any(matching)
                else:
                    matches = document.get("config", {}).get("digest") == config_id
                visiting.remove(digest)
                if matches:
                    identities.add(digest)
                return matches

            for descriptor in index["manifests"]:
                matches_config(descriptor)
        return config_id, identities


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("archive")
    parser.add_argument("--expected")
    parser.add_argument("--loaded")
    args = parser.parse_args()
    config_id, identities = image_ids(args.archive)
    for label, identity in (("release", args.expected), ("loaded", args.loaded)):
        if identity is not None and identity not in identities:
            raise ValueError(f"{label} image ID does not match the verified archive")
    print(config_id)


if __name__ == "__main__":
    main()
