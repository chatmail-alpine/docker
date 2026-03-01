import os
import shutil
from pathlib import Path

from dataclasses import dataclass

import chatmaild.config
from jinja2 import Environment


@dataclass
class GenCfg:
    src_dir: Path
    ins_dir: Path
    cmd: chatmaild.config.Config

    @classmethod
    def from_env(cls) -> 'GenCfg':
        src_dir = Path(os.getenv('SRCDIR', '/template'))
        ins_dir = Path(os.getenv('INSDIR', '/instance'))
        cmd_path = ins_dir / 'chatmail.ini'
        cmd = chatmaild.config.read_config(cmd_path)
        return cls(src_dir, ins_dir, cmd)


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
                mkdirs(dst)
                with dst.open('wt', encoding='utf-8') as f:
                    f.write(tmpl.render(**cmd_obj))
            else:
                # simply copy the file
                dst = cfg_dst / parent / file
                mkdirs(dst)
                shutil.copy(src, dst)


def mkdirs(p: Path) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)


if __name__ == '__main__':
    gc = GenCfg.from_env()
    render_cfg(gc)
