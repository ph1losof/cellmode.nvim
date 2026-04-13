#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys


def parse_args():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--tir-csv", dest="tir_csv", default="tir-csv")
    parser.add_argument("--delimiter", dest="delimiter", default=None)
    return parser.parse_args()


def encode_id(path, fmt):
    abs_path = os.path.abspath(path)
    return f"{fmt}:{abs_path}"


def decode_id(workbook_id):
    if not isinstance(workbook_id, str) or ":" not in workbook_id:
        return None, None
    fmt, path = workbook_id.split(":", 1)
    if fmt == "" or path == "":
        return None, None
    return fmt, path


def error(req_id, code, message, data=None):
    payload = {
        "jsonrpc": "2.0",
        "id": req_id,
        "error": {
            "code": code,
            "message": message,
        },
    }
    if data is not None:
        payload["error"]["data"] = data
    return payload


def result(req_id, obj):
    return {
        "jsonrpc": "2.0",
        "id": req_id,
        "result": obj,
    }


def delimiter_for_format(fmt, override):
    if override is not None:
        return override
    if fmt == "tsv":
        return "\t"
    return ","


def run_tir_csv(executable, subcmd, delimiter, input_text):
    command = [executable, subcmd]
    if delimiter is not None:
        command.extend(["--delimiter", delimiter])
    proc = subprocess.run(
        command,
        input=input_text,
        text=True,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        stderr = proc.stderr.strip() or "(no stderr output)"
        raise RuntimeError(stderr)
    return proc.stdout


def read_text_lines(path):
    if not os.path.exists(path):
        return []
    with open(path, "r", encoding="utf-8") as fp:
        return fp.read().splitlines()


def csv_to_sheet(executable, path, fmt, delimiter):
    fl_lines = read_text_lines(path)
    input_text = "\n".join(fl_lines)
    js_string = run_tir_csv(executable, "parse", delimiter, input_text)
    rows = []
    for line in js_string.splitlines():
        if not line:
            continue
        nd = json.loads(line)
        if nd.get("kind") == "grid":
            row = nd.get("row") or []
            rows.append([str(cell) for cell in row])
    return {
        "id": "sheet1",
        "name": "Sheet1",
        "segments": [
            {"kind": "table", "rows": rows},
        ],
    }


def csv_to_workbook(executable, workbook_id, fmt, path, delimiter):
    sheet = csv_to_sheet(executable, path, fmt, delimiter)
    return {
        "id": workbook_id,
        "format": fmt,
        "active_sheet": 1,
        "sheets": [sheet],
    }


def workbook_to_ndjson_lines(workbook):
    active_sheet_index = workbook.get("active_sheet")
    sheets = workbook.get("sheets") or []
    if isinstance(active_sheet_index, int) and 1 <= active_sheet_index <= len(sheets):
        sheet = sheets[active_sheet_index - 1]
    elif sheets:
        sheet = sheets[0]
    else:
        sheet = {"segments": []}

    rows = []
    for segment in sheet.get("segments") or []:
        if segment.get("kind") == "table":
            rows.extend(segment.get("rows") or [])
            break

    lines = [{"kind": "attr_file"}]
    for row in rows:
        lines.append(
            {
                "kind": "grid",
                "row": ["" if cell is None else str(cell) for cell in row],
            }
        )
    return [json.dumps(item, ensure_ascii=False) for item in lines]


def write_csv(executable, workbook, path, fmt, delimiter):
    js_lines = workbook_to_ndjson_lines(workbook)
    js_text = "\n".join(js_lines)
    fl_text = run_tir_csv(executable, "unparse", delimiter, js_text)
    with open(path, "w", encoding="utf-8") as fp:
        fp.write(fl_text)


def handle(request, args):
    req_id = request.get("id")
    method = request.get("method")
    params = request.get("params") or {}

    if method == "capabilities":
        return result(
            req_id,
            {
                "name": "cellmode-tir-csv-adapter",
                "methods": {
                    "open": True,
                    "read_workbook": True,
                    "write_workbook": True,
                },
                "features": {
                    "streaming": False,
                    "formulas": False,
                    "styles": False,
                    "multi_sheet": False,
                },
            },
        )

    if method == "open":
        path = params.get("path")
        fmt = params.get("format")
        if not isinstance(path, str) or path == "":
            return error(req_id, 1001, "path is required")
        if fmt not in ("csv", "tsv"):
            return error(req_id, 1001, "format must be csv or tsv")
        workbook_id = encode_id(path, fmt)
        return result(req_id, {"workbook_id": workbook_id, "meta": {}})

    if method == "list_sheets":
        fmt, _ = decode_id(params.get("workbook_id"))
        if fmt is None:
            return error(req_id, 1100, "invalid workbook_id")
        return result(
            req_id,
            {
                "sheets": [{"id": "sheet1", "name": "Sheet1"}],
            },
        )

    if method == "read_sheet":
        workbook_id = params.get("workbook_id")
        fmt, path = decode_id(workbook_id)
        if fmt is None:
            return error(req_id, 1100, "invalid workbook_id")
        try:
            delimiter = delimiter_for_format(fmt, args.delimiter)
            sheet = csv_to_sheet(args.tir_csv, path, fmt, delimiter)
        except Exception as exc:
            return error(req_id, 1200, "parse failure", {"reason": str(exc)})
        return result(req_id, {"sheet": sheet})

    if method == "read_workbook":
        workbook_id = params.get("workbook_id")
        fmt, path = decode_id(workbook_id)
        if fmt is None:
            return error(req_id, 1100, "invalid workbook_id")
        try:
            delimiter = delimiter_for_format(fmt, args.delimiter)
            workbook = csv_to_workbook(args.tir_csv, workbook_id, fmt, path, delimiter)
        except Exception as exc:
            return error(req_id, 1200, "parse failure", {"reason": str(exc)})
        return result(req_id, workbook)

    if method == "write_workbook":
        workbook = params.get("workbook")
        path = params.get("path")
        fmt = params.get("format")
        if not isinstance(workbook, dict):
            return error(req_id, 1001, "workbook is required")
        if not isinstance(path, str) or path == "":
            return error(req_id, 1001, "path is required")
        if fmt not in ("csv", "tsv"):
            return error(req_id, 1001, "format must be csv or tsv")
        try:
            delimiter = delimiter_for_format(fmt, args.delimiter)
            write_csv(args.tir_csv, workbook, path, fmt, delimiter)
        except Exception as exc:
            return error(req_id, 1201, "serialize failure", {"reason": str(exc)})
        return result(req_id, {"ok": True})

    return error(req_id, 1002, "unsupported method", {"method": method})


def main():
    args = parse_args()
    for line in sys.stdin:
        if not line:
            continue
        try:
            request = json.loads(line)
        except Exception:
            print(
                json.dumps(error(None, 1001, "invalid json"), ensure_ascii=False),
                flush=True,
            )
            continue
        print(json.dumps(handle(request, args), ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
