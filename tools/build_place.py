"""src/ 폴더의 스크립트들을 Studio에서 바로 열 수 있는 TycoonGame.rbxlx 한 파일로 묶는다.
사용법: python3 tools/build_place.py
"""
import os
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_ref = 0


def ref():
    global _ref
    _ref += 1
    return f"RBX{_ref:08X}"


def cdata(text):
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def item(cls, name, children="", source=None):
    props = f'<string name="Name">{escape(name)}</string>'
    if source is not None:
        props += f'<ProtectedString name="Source">{cdata(source)}</ProtectedString>'
    return f'<Item class="{cls}" referent="{ref()}"><Properties>{props}</Properties>{children}</Item>\n'


def script_item(path):
    fname = os.path.basename(path)
    with open(path, encoding="utf-8") as f:
        src = f.read()
    if fname.endswith(".server.luau"):
        return item("Script", fname[: -len(".server.luau")], source=src)
    if fname.endswith(".client.luau"):
        return item("LocalScript", fname[: -len(".client.luau")], source=src)
    return item("ModuleScript", fname[: -len(".luau")], source=src)


def folder_items(rel):
    d = os.path.join(ROOT, rel)
    return "".join(script_item(os.path.join(d, f)) for f in sorted(os.listdir(d)) if f.endswith(".luau"))


body = (
    item("Workspace", "Workspace")
    + item("ReplicatedStorage", "ReplicatedStorage", item("Folder", "Shared", folder_items("src/shared")))
    + item("ServerScriptService", "ServerScriptService", item("Folder", "Server", folder_items("src/server")))
    + item("StarterPlayer", "StarterPlayer",
           item("StarterPlayerScripts", "StarterPlayerScripts", item("Folder", "Client", folder_items("src/client"))))
)

xml = (
    '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
    'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
    + body + "</roblox>\n"
)

out = os.path.join(ROOT, "TycoonGame.rbxlx")
with open(out, "w", encoding="utf-8") as f:
    f.write(xml)
print("wrote", out, len(xml), "bytes")
