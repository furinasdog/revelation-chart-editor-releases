"""Isolated protocol worker. Untrusted source is interpreted, never compiled."""

import ast
import json
import math
import operator
import runpy
import sys
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rpy

MAX_SOURCE = 32768
MAX_OUTPUT = 131072
MAX_STEPS = 20000
MAX_VALUES = 4096
OPERATORS = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
             ast.Div: operator.truediv, ast.FloorDiv: operator.floordiv, ast.Mod: operator.mod}
COMPARISONS = {ast.Eq: operator.eq, ast.NotEq: operator.ne, ast.Lt: operator.lt, ast.LtE: operator.le,
               ast.Gt: operator.gt, ast.GtE: operator.ge, ast.In: lambda a, b: a in b,
               ast.NotIn: lambda a, b: a not in b}


class Log:
    def __init__(self):
        self.value = ""

    def write(self, text):
        self.value = (self.value + text[:16384])[:16384]
        return len(text)

    def flush(self):
        pass


class Interpreter:
    def __init__(self, chart, log):
        self.remaining = MAX_STEPS
        self.values = {}
        self.methods = {name: getattr(chart, name) for name in
                        ("notes", "read", "pitch", "reference", "edit", "scale_hold_paths", "draw", "field", "linspace")}
        self.functions = {"len": len, "min": min, "max": max, "abs": abs, "round": round, "int": int,
                          "float": float, "str": str, "result": rpy.result,
                          "print": lambda *parts: log.write(" ".join(map(str, parts)) + "\n"),
                          "range": self.make_range}

    @staticmethod
    def make_range(*arguments):
        values = range(*arguments)
        if len(values) > MAX_VALUES:
            raise ValueError("Loop range too large")
        return list(values)

    def tick(self):
        self.remaining -= 1
        if self.remaining < 0:
            raise ValueError("Script operation limit reached")

    def block(self, nodes):
        for node in nodes:
            self.tick()
            if isinstance(node, ast.Expr):
                self.expression(node.value)
            elif isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
                self.assign(node.targets[0].id, self.expression(node.value))
            elif isinstance(node, ast.If):
                self.block(node.body if self.expression(node.test) else node.orelse)
            elif isinstance(node, ast.For) and isinstance(node.target, ast.Name) and not node.orelse:
                values = self.expression(node.iter)
                if not isinstance(values, (list, tuple, dict)) or len(values) > MAX_VALUES:
                    raise ValueError("Unsupported or excessively large iteration")
                for value in values:
                    self.tick()
                    self.assign(node.target.id, value)
                    self.block(node.body)
            else:
                raise ValueError(f"Unsupported statement at line {node.lineno}: {type(node).__name__}")

    def assign(self, name, value):
        if name.startswith("_") or len(self.values) >= 256 and name not in self.values:
            raise ValueError("Invalid script variable")
        self.values[name] = self.bounded(value)

    def expression(self, node):
        self.tick()
        if isinstance(node, ast.Constant) and type(node.value) in (str, int, float, bool, type(None)):
            return self.bounded(node.value)
        if isinstance(node, ast.Name) and node.id in self.values:
            return self.values[node.id]
        if isinstance(node, (ast.List, ast.Tuple)):
            return self.bounded([self.expression(value) for value in node.elts])
        if isinstance(node, ast.Dict) and all(key is not None for key in node.keys):
            return self.bounded({self.expression(key): self.expression(value) for key, value in zip(node.keys, node.values)})
        if isinstance(node, ast.Subscript) and not isinstance(node.slice, ast.Slice):
            value = self.expression(node.value)
            if isinstance(value, (dict, list, str)):
                return value[self.expression(node.slice)]
        if isinstance(node, ast.IfExp):
            return self.expression(node.body if self.expression(node.test) else node.orelse)
        if isinstance(node, ast.BoolOp):
            result = None
            for item in node.values:
                result = self.expression(item)
                if bool(result) == isinstance(node.op, ast.Or):
                    break
            return result
        if isinstance(node, ast.UnaryOp):
            value = self.expression(node.operand)
            if isinstance(node.op, ast.Not):
                return not value
            if isinstance(node.op, (ast.USub, ast.UAdd)) and type(value) in (int, float):
                return -value if isinstance(node.op, ast.USub) else value
        if isinstance(node, ast.BinOp) and type(node.op) in OPERATORS:
            lhs, rhs = self.expression(node.left), self.expression(node.right)
            if type(lhs) in (int, float) and type(rhs) in (int, float):
                return self.bounded(OPERATORS[type(node.op)](lhs, rhs))
            if isinstance(node.op, ast.Add) and type(lhs) is type(rhs) and isinstance(lhs, (str, list)):
                return self.bounded(lhs + rhs)
        if isinstance(node, ast.Compare) and all(type(op) in COMPARISONS for op in node.ops):
            lhs = self.expression(node.left)
            for op, other in zip(node.ops, node.comparators):
                rhs = self.expression(other)
                if not COMPARISONS[type(op)](lhs, rhs):
                    return False
                lhs = rhs
            return True
        if isinstance(node, ast.Call):
            function = None
            if isinstance(node.func, ast.Name):
                function = self.functions.get(node.func.id)
            elif isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name) and node.func.value.id in {"rpy", "chart"}:
                function = self.methods.get(node.func.attr)
            if function is not None and all(kw.arg is not None for kw in node.keywords):
                if function == str:
                    return self.bounded(str(*[self.expression(value) for value in node.args]))
                return self.bounded(function(*[self.expression(value) for value in node.args],
                                             **{kw.arg: self.expression(kw.value) for kw in node.keywords}))
        raise ValueError(f"Unsupported expression at line {node.lineno}: {type(node).__name__}")

    @staticmethod
    def bounded(value):
        pending = [(value, 0)]
        remaining = 32768
        while pending:
            item, depth = pending.pop()
            remaining -= 1
            if remaining < 0 or depth > 24:
                raise ValueError("Value exceeds structure limits")
            if type(item) in (int, float) and (abs(item) > 1e12 or not math.isfinite(item)):
                raise ValueError("Numeric result exceeds limits")
            if isinstance(item, (str, list, dict)) and len(item) > MAX_VALUES:
                raise ValueError("Value exceeds limits")
            if isinstance(item, list):
                pending.extend((part, depth + 1) for part in item)
            elif isinstance(item, dict):
                pending.extend((part, depth + 1) for part in item.values())
        return value


def run(request, log):
    mode = request["mode"]
    source = request.get("source", "")
    if mode != "trusted" and (not isinstance(source, str) or len(source.encode("utf-8")) > MAX_SOURCE):
        raise ValueError("Script too large")
    chart = rpy.Chart(request["snapshot"])
    rpy.chart = chart
    rpy._result = None
    if mode == "restricted":
        Interpreter(chart, log).block(ast.parse(source, mode="exec").body)
    elif mode == "trusted":
        with redirect_stdout(log):
            runpy.run_path(request["script"], run_name="__main__")
    else:
        raise ValueError("Unknown script mode")
    return {"actions": chart.actions, "result": rpy._result, "log": log.value}


def main():
    request, response = map(Path, sys.argv[1:3])
    log = Log()
    try:
        outcome = run(json.loads(request.read_text("utf-8")), log)
        content = json.dumps(outcome, ensure_ascii=False, allow_nan=False).encode()
        if len(content) > MAX_OUTPUT:
            raise ValueError("Script output and draft exceed 128 KiB")
    except Exception as exc:
        content = json.dumps({"error": str(exc)[:300], "log": log.value}, ensure_ascii=False).encode()
    response.write_bytes(content)


if __name__ == "__main__":
    main()
