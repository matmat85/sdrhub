import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest


spec = importlib.util.spec_from_file_location(
    "image_archive", Path(__file__).resolve().parents[1] / "scripts/image_archive.py"
)
image_archive = importlib.util.module_from_spec(spec)
spec.loader.exec_module(image_archive)


class ImageArchiveTests(unittest.TestCase):
    def fixture(self, directory, oci=False, corrupt=False, tag="loft/sdr-hub:local"):
        entries = {}

        def blob(document):
            content = json.dumps(document).encode()
            digest = "sha256:" + hashlib.sha256(content).hexdigest()
            entries["blobs/sha256/" + digest[7:]] = content
            return digest

        config_id = blob({"os": "linux", "architecture": "amd64"})
        manifest_id = blob({"config": {"digest": config_id}, "layers": []})
        index_id = blob({"manifests": [{"digest": manifest_id}]})
        entries["manifest.json"] = json.dumps([{
            "RepoTags": [tag], "Config": "blobs/sha256/" + config_id[7:], "Layers": []
        }]).encode()
        if oci:
            entries["index.json"] = json.dumps({"manifests": [{"digest": index_id}]}).encode()
        if corrupt:
            entries["blobs/sha256/" + manifest_id[7:]] += b" "
        path = Path(directory) / "image.tar.gz"
        with tarfile.open(path, "w:gz") as archive:
            for name, content in entries.items():
                member = tarfile.TarInfo(name)
                member.size = len(content)
                archive.addfile(member, io.BytesIO(content))
        return path, config_id, manifest_id, index_id

    def test_classic_config_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            path, config_id, _, _ = self.fixture(directory)
            self.assertEqual(image_archive.image_ids(path), (config_id, {config_id}))

    def test_containerd_and_classic_ids_match_same_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            path, config_id, manifest_id, index_id = self.fixture(directory, oci=True)
            self.assertEqual(image_archive.image_ids(path),
                             (config_id, {config_id, manifest_id, index_id}))

    def test_corrupt_descriptor_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path, _, _, _ = self.fixture(directory, oci=True, corrupt=True)
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                image_archive.image_ids(path)

    def test_wrong_tag_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path, _, _, _ = self.fixture(directory, tag="unrelated:local")
            with self.assertRaisesRegex(ValueError, "exactly one"):
                image_archive.image_ids(path)

    def test_unknown_release_or_loaded_id_rejected(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as directory:
            path, config_id, _, index_id = self.fixture(directory, oci=True)
            for option in ("--expected", "--loaded"):
                with patch("sys.argv", ["image_archive", str(path), option, "sha256:" + "0" * 64]):
                    with self.assertRaisesRegex(ValueError, "does not match"):
                        image_archive.main()
            with patch("sys.argv", ["image_archive", str(path), "--expected", config_id,
                                   "--loaded", index_id]):
                with patch("sys.stdout", new_callable=io.StringIO) as output:
                    image_archive.main()
                self.assertEqual(output.getvalue(), config_id + "\n")


if __name__ == "__main__":
    unittest.main()
