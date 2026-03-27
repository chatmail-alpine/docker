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
    is_root: bool

    @classmethod
    def from_env(cls) -> 'GenCfg':
        src_dir = Path(os.getenv('SRCDIR', '/template'))
        ins_dir = Path(os.getenv('INSDIR', '/instance'))
        cmd_path = ins_dir / 'chatmail.ini'
        cmd = chatmaild.config.read_config(cmd_path)
        is_root = os.getuid() == 0
        return cls(src_dir, ins_dir, cmd, is_root)


def render_cfg(gc: GenCfg) -> None:
    j2_env = Environment(autoescape=False)
    cmd_obj = gc.cmd.__dict__
    cmd_obj['dkim_selector'] = 'opendkim'

    cfg_src = gc.src_dir / 'config'
    cfg_dst = gc.ins_dir / 'config'

    def _render_j2(src: Path, dst: Path, ctx: dict[str, object]) -> None:
        with src.open('rt', encoding='utf-8') as f:
            tmpl = j2_env.from_string(f.read())
        _mkdirs(dst)
        with dst.open('wt', encoding='utf-8') as f:
            f.write(tmpl.render(**ctx))

    for parent, _, files in cfg_src.walk():
        for file in files:
            src = parent / file
            src_rel = src.relative_to(cfg_src)
            ext = src.suffix
            if ext == '.j2':
                # render the template
                _render_j2(
                    src=src,
                    # we put rendered cfg.j2 into cfg
                    dst=cfg_dst / src_rel.with_suffix(''),
                    ctx=cmd_obj,
                )
            elif ext == '.no-tls':
                # same but add no_tls=true into template context
                _render_j2(
                    # actual tmpl for cfg.no-tls is cfg.j2
                    src=src.with_suffix('.j2'),
                    # we put rendered cfg.no-tls into cfg.no-tls
                    dst=cfg_dst / src_rel,
                    ctx={**cmd_obj, 'no_tls': True},
                )
            else:
                # simply copy the file
                dst = cfg_dst / src_rel
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
    _init_dir(gc, rm=True, tree=GenDirectory(
        path=gc.ins_dir / 'socket',
        owner=0,
        group=0,
        contents=[
            GenDirectory('lastlogin'),
            GenDirectory('metadata'),
            GenDirectory('chatmail-turn'),
            GenDirectory('doveauth'),
            GenDirectory('newemail', *NGINX_UG),
            GenDirectory('opendkim-postfix', *DKIM_UG, mode=0o750),
        ],
    ))


def fix_cfg_perms(gc: GenCfg) -> None:
    _init_dir(gc, GenDirectory(
        path=gc.ins_dir / 'config',
        owner=0,
        group=0,
        contents=[
            GenDirectory('tls', 0, 0, 0o750),
            GenDirectory('opendkim', 0, DKIM_UG[1]),
            GenDirectory('dkimkeys', *DKIM_UG, 0o750),
        ],
    ))


def init_datadirs(gc: GenCfg) -> None:
    _init_dir(gc, GenDirectory(
        path=gc.ins_dir / 'data',
        owner=0,
        group=0,
        contents=[
            GenDirectory('vmail', contents=[
                GenDirectory('mail', contents=[
                    # vmail/mail/chat.example.com
                    GenDirectory(gc.cmd.mail_domain),
                ]),
            ]),
            GenDirectory('postfix', 0, 0),
            GenDirectory('certbot', 0, 0, contents=[
                GenDirectory('etc', 0, 0, 0o750),
                GenDirectory('var', 0, 0, 0o750),
                GenDirectory('web', 0, 0),
            ]),
        ],
    ))


def _init_dir(gc: GenCfg, tree: GenDirectory, rm: bool = False) -> None:
    root = tree.path
    assert root is not None
    root.mkdir(mode=tree.mode, exist_ok=True)
    _chown_one(gc, root, tree.owner, tree.group)

    stack: list[GenDirectory] = []

    def _add_with_paths(parent: Path, it: Iterable[GenDirectory]) -> None:
        if not it:
            return
        for i in it:
            i.path = parent / i.name
            stack.append(i)

    _add_with_paths(root, tree.contents)
    while stack:
        item = stack.pop()
        path = item.path
        if rm and path.exists():
            shutil.rmtree(path)
        path.mkdir(mode=item.mode, exist_ok=True)
        _chown_one(gc, path, item.owner, item.group)
        _add_with_paths(path, item.contents)


def _chown_one(gc: GenCfg, p: Path, uid: int, gid: int) -> None:
    if gc.is_root:
        os.chown(p, uid, gid)
    else:
        print(f'Skipping chown {uid}:{gid} "{p}"')


if __name__ == '__main__':
    gc = GenCfg.from_env()
    gc.ins_dir.chmod(0o755)
    render_cfg(gc)
    render_web(gc)
    init_rundirs(gc)
    fix_cfg_perms(gc)
    init_datadirs(gc)
