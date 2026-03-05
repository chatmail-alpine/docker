import os
import shutil
from pathlib import Path

from dataclasses import dataclass
from typing import Iterable

import chatmaild.config
from jinja2 import Environment, FileSystemLoader
from markdown import markdown


@dataclass
class GenCfg:
    src_dir: Path
    ins_dir: Path
    cmd: chatmaild.config.Config
    ready: Path

    @classmethod
    def from_env(cls) -> 'GenCfg':
        src_dir = Path(os.getenv('SRCDIR', '/template'))
        ins_dir = Path(os.getenv('INSDIR', '/instance'))
        cmd_path = ins_dir / 'chatmail.ini'
        cmd = chatmaild.config.read_config(cmd_path)
        ready = Path(os.getenv('READYFILE', '/ready'))
        return cls(src_dir, ins_dir, cmd, ready)


def render_cfg(gc: GenCfg) -> None:
    j2_env = Environment(autoescape=False)
    cmd_obj = gc.cmd.__dict__
    cmd_obj['dkim_selector'] = 'opendkim'

    cfg_src = gc.src_dir / 'config'
    cfg_dst = gc.ins_dir / 'config'

    for parent, _, files in cfg_src.walk():
        for file in files:
            src = parent / file
            parent_rel = parent.relative_to(cfg_src)
            if file.endswith('.j2'):
                # render the template
                with src.open('rt', encoding='utf-8') as f:
                    tmpl = j2_env.from_string(f.read())
                dst = cfg_dst / parent_rel / file.removesuffix('.j2')
                _mkdirs(dst)
                with dst.open('wt', encoding='utf-8') as f:
                    f.write(tmpl.render(**cmd_obj))
            else:
                # simply copy the file
                dst = cfg_dst / parent_rel / file
                _mkdirs(dst)
                shutil.copy(src, dst)


def render_web(gc: GenCfg) -> None:
    web_src = gc.src_dir / 'web'
    web_dst = gc.ins_dir / 'web'

    j2_env = Environment(loader=FileSystemLoader(web_src))
    j2_env.filters['markdown'] = _md2html
    cmd_obj = gc.cmd.__dict__

    for parent, _, files in web_src.walk():
        parent_rel = parent.relative_to(web_src)
        parts = parent_rel.parts
        first_dir = parts[0] if len(parts) > 0 else ''
        if first_dir == 'layout':
            continue
        elif first_dir == 'static':
            # simply copy files to webroot
            # removing ./static/ prefix
            parent_rel = parent_rel.relative_to(first_dir)
            for file in files:
                src = web_src / parent / file
                dst = web_dst / parent_rel / file
                _mkdirs(dst)
                shutil.copy(src, dst)
        else:
            # render as page templates
            for file in files:
                tmpl = j2_env.get_template(os.fspath(parent_rel / file))
                dst = (web_dst / parent_rel / file).with_suffix('')
                if dst.name == 'index':
                    dst = dst.with_suffix('.html')
                else:
                    dst = dst / 'index.html'
                _mkdirs(dst)
                with dst.open('wt', encoding='utf-8') as f:
                    f.write(tmpl.render(**cmd_obj))


def _md2html(value: str) -> str:
    return markdown(
        text=value,
        extensions=['fenced_code'],
        output_format='html',
        tab_length=2,
    )


def _mkdirs(p: Path) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)


VMAIL_UG = 501, 501
NGINX_UG = 101, 101
POSTFIX_UG = 201, 201
DKIM_UG = 202, 202

@dataclass
class GenDirectory:
    name: str = ''
    owner: int = VMAIL_UG[0]
    group: int = VMAIL_UG[1]
    mode: int = 0o755
    contents: list['GenDirectory'] | None = None
    path: Path | None = None


def init_rundirs(gc: GenCfg) -> None:
    _init_dir(rm=True, tree=GenDirectory(
        path=gc.ins_dir / 'socket',
        owner=0,
        group=0,
        contents=[
            GenDirectory('chatmail-lastlogin', *VMAIL_UG),
            GenDirectory('chatmail-metadata', *VMAIL_UG),
            GenDirectory('chatmail-turn', *VMAIL_UG),
            GenDirectory('doveauth', *VMAIL_UG),
            GenDirectory('newemail', *NGINX_UG),
        ],
    ))


def _init_dir(tree: GenDirectory, rm: bool = False) -> None:
    root = tree.path
    assert root is not None
    root.mkdir(mode=tree.mode, exist_ok=True)
    os.chown(root, tree.owner, tree.group)

    stack: list[GenDirectory] = []

    def _add_with_paths(it: Iterable[GenDirectory]) -> None:
        if not it:
            return
        for i in it:
            i.path = root / i.name
            stack.append(i)

    _add_with_paths(tree.contents)
    while stack:
        item = stack.pop()
        path = item.path
        if rm and path.exists():
            shutil.rmtree(path)
        path.mkdir(mode=item.mode)
        os.chown(path, item.owner, item.group)
        _add_with_paths(item.contents)


if __name__ == '__main__':
    gc = GenCfg.from_env()
    render_cfg(gc)
    render_web(gc)
    init_rundirs(gc)
    gc.ready.touch()
