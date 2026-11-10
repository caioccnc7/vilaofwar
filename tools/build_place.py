"""Gera FibraDaVila.rbxlx a partir da pasta src/, sem precisar do Rojo.
Uso: python3 tools/build_place.py

Serve para testar o código num place local. O jogo oficial é a experiência
"Provedor de Internet": nela o código entra pelos modelos (tools/gen_models.py).
"""
import os, uuid
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAP = [
    ("ReplicatedStorage", None, "Shared", "src/shared"),
    ("ServerScriptService", None, "Server", "src/server"),
    ("StarterPlayer", "StarterPlayerScripts", "Client", "src/client"),
]

def ref():
    return "RBX" + uuid.uuid4().hex.upper()

def cdata(text):
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"

def item(cls, name, children="", source=None):
    props = f'<string name="Name">{escape(name)}</string>'
    if source is not None:
        props += f'<ProtectedString name="Source">{cdata(source)}</ProtectedString>'
    return f'<Item class="{cls}" referent="{ref()}"><Properties>{props}</Properties>{children}</Item>'

def folder_items(path):
    out = []
    for entry in sorted(os.listdir(path)):
        full = os.path.join(path, entry)
        if os.path.isdir(full):
            out.append(item("Folder", entry, "".join(folder_items(full))))
            continue
        if not entry.endswith((".luau", ".lua")):
            continue
        base = entry.rsplit(".", 1)[0]
        src = open(full, encoding="utf-8").read()
        if base.endswith(".server"):
            out.append(item("Script", base[:-7], source=src))
        elif base.endswith(".client"):
            out.append(item("LocalScript", base[:-7], source=src))
        else:
            out.append(item("ModuleScript", base, source=src))
    return out

def main():
    services = {}
    for service, sub, name, rel in MAP:
        inner = item("Folder", name, "".join(folder_items(os.path.join(ROOT, rel))))
        if sub:
            inner = item(sub, sub, inner)
        services.setdefault(service, []).append(inner)
    body = item("Workspace", "Workspace")
    for service, kids in services.items():
        body += item(service, service, "".join(kids))
    xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmime" '
           'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
           'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
           + body + '</roblox>')
    out = os.path.join(ROOT, "FibraDaVila.rbxlx")
    open(out, "w", encoding="utf-8").write(xml)
    print("gerado:", out, len(xml), "bytes")

if __name__ == "__main__":
    main()
