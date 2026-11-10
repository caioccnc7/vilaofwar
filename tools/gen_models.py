"""Gera os modelos para importar no Roblox Studio (Arquivo > Importar modelo).

Uso: python3 tools/gen_models.py <prefixo>
Saída: modelos/<prefixo>_Shared.rbxmx, _Server.rbxmx e _Client.rbxmx
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_place import ROOT, item, folder_items  # noqa: E402

HEADER = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmime" '
          'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
          'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">')


def main():
    if len(sys.argv) != 2:
        sys.exit("uso: python3 tools/gen_models.py <prefixo>")
    prefix = sys.argv[1]
    out_dir = os.path.join(ROOT, "modelos")
    os.makedirs(out_dir, exist_ok=True)
    for name, rel in [("Shared", "src/shared"), ("Client", "src/client"), ("Server", "src/server")]:
        xml = item("Folder", name, "".join(folder_items(os.path.join(ROOT, rel))))
        path = os.path.join(out_dir, f"{prefix}_{name}.rbxmx")
        with open(path, "w", encoding="utf-8") as f:
            f.write(HEADER + xml + "</roblox>")
        print("gerado:", path)


if __name__ == "__main__":
    main()
