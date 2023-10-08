#
# # Copyright © 2023 krishnakumar <ksquarekumar@gmail.com>.
# #
# # Licensed under the Apache License, Version 2.0 (the "License"). You
# # may not use this file except in compliance with the License. A copy of
# # the License is located at:
# #
# # https://github.com/ksquarekumar/jupyter-docker/blob/main/LICENSE
# #
# # or in the "license" file accompanying this file. This file is
# # distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
# # ANY KIND, either express or implied. See the License for the specific
# # language governing permissions and limitations under the License.
# #
# # This file is part of the jupyter-docker project.
# # see (https://github.com/ksquarekumar/jupyter-docker)
# #
# # SPDX-License-Identifier: Apache-2.0
# #
# # You should have received a copy of the APACHE LICENSE, VERSION 2.0
# # along with this program. If not, see <https://apache.org/licenses/LICENSE-2.0>
#
import os
import logging
from typing import Any

logger = logging.getLogger(__name__)
logger.setLevel("INFO")

HERE = os.path.dirname(os.path.abspath(__file__))


def get_codeserver_executable(prog: Any):
    from shutil import which

    # check the special environment variable
    if os.getenv("CODESERVER_BIN") is not None:
        return os.getenv("CODESERVER_BIN")

    # check the bin directory of this package
    wp = os.path.join(HERE, "bin", prog)
    if os.path.exists(wp):
        return wp

    # check the system path
    if which(prog):
        return prog

    # check at known locations
    other_paths = [
        os.path.join("/opt/codeserver/bin", prog),
    ]
    for op in other_paths:
        if os.path.exists(op):
            return op

    raise FileNotFoundError(f"Could not find {prog} in PATH")


def _codeserver_urlparams():
    from getpass import getuser

    url_params = "?" + "&".join(
        [
            "username=" + getuser(),
            "password=" + _codeserver_passwd,
            "sharing=true",
        ]
    )

    return url_params


def _codeserver_mappath(path: str):
    # always pass the url parameter
    if path in (
        "/",
        "/index.html",
    ):
        url_params = _codeserver_urlparams()
        path = "/index.html" + url_params

    return path


def setup_codeserver():
    """Setup commands and and return a dictionary compatible
    with jupyter-server-proxy.
    """
    from tempfile import mkstemp
    from random import choice
    from string import ascii_letters, digits

    global _codeserver_passwd, _codeserver_aeskey

    # password generator
    def _get_random_alphanumeric_string(length: int):
        letters_and_digits = ascii_letters + digits
        return "".join((choice(letters_and_digits) for _ in range(length)))

    # generate file with random one-time-password
    _codeserver_passwd = _get_random_alphanumeric_string(16)
    try:
        fd_passwd, fpath_passwd = mkstemp()
        logger.info("Created secure password file for codeserver: " + fpath_passwd)

        with open(fd_passwd, "w") as f:
            f.write(_codeserver_passwd)

    except Exception:
        logger.error("Passwd generation in temp file FAILED")
        raise FileNotFoundError("Passwd generation in temp file FAILED")

    # launchers url file including url parameters
    # path_info = 'codeserver/index.html' + _codeserver_urlparams()

    # create command
    cmd = [
        get_codeserver_executable("code-server"),
        "--auth=none",  # password
        "--disable-telemetry",
        "--disable-update-check",
        "--bind-addr=0.0.0.0:{port}",
        # '--user-data-dir=<path>',  # default: ~/.local/share/code-server
        # '--config=<path>',  # default: ~/.config/code-server/config.yaml
        # '--extensions-dir=<path>',  # default: .local/share/code-server/extensions
        "--verbose",
    ]
    logger.info("Code-Server command: " + " ".join(cmd))

    return {
        "environment": {},
        "command": cmd,
        "mappath": _codeserver_mappath,
        "absolute_url": False,
        "timeout": 90,
        "new_browser_tab": True,
        "launcher_entry": {
            "enabled": True,
            "icon_path": os.path.join(HERE, "icons/code-server-logo.svg"),
            "title": "VS Code (code-server)",
            # 'path_info': path_info,
        },
    }
