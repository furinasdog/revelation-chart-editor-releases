"""Chart scripting interface. The editor applies recorded actions to its draft."""

from copy import deepcopy
from math import isfinite

MAX_ACTIONS = 128
WRITES = frozenset({
    "add_notes", "delete_notes", "move_notes", "set_positions", "resize_holds",
    "set_note_lead_in", "set_hold_path", "scale_hold_paths", "set_chart_metadata",
    "set_tempo_map", "upsert_text_event", "delete_text_event", "create_shape_asset",
    "create_solid_mask", "set_mask_cue", "add_mask_reveal", "add_animation_layer",
    "update_animation_layer", "remove_animation_layer", "set_project_artwork", "set_artwork_cue",
})


class Chart:
    def __init__(self, snapshot):
        self._snapshot = snapshot
        self.actions = []

    def notes(self, start=0, end=None, kind="", offset=0, limit=128):
        rows = self._snapshot["notes"]
        if end is None:
            end = self._snapshot["project"]["duration_ms"]
        if not 0 <= offset <= len(rows) or not 1 <= limit <= 1024:
            raise ValueError("Invalid note page")
        matches = [n for n in rows if start <= n["time_ms"] <= end and (not kind or n["type"] == kind)]
        return deepcopy(matches[offset:offset + limit])

    def read(self, section):
        if section not in {"project", "events", "animations", "artwork", "tempo", "pitch", "references"}:
            raise ValueError("Unknown chart section")
        return deepcopy(self._snapshot.get(section, {}))

    def edit(self, action, **arguments):
        if action not in WRITES:
            raise ValueError("Unsupported edit: " + str(action))
        if len(self.actions) >= MAX_ACTIONS:
            raise ValueError("Too many draft actions")
        self.actions.append({"name": action, "arguments": deepcopy(arguments)})
        return {"action_index": len(self.actions) - 1}

    def scale_hold_paths(self, start, end, factor):
        if not isfinite(factor) or not 0.1 <= factor <= 4 or start > end:
            raise ValueError("Invalid hold path span or scale")
        return self.edit("scale_hold_paths", from_ms=start, to_ms=end, factor=factor)

    @staticmethod
    def field(action, field):
        if not isinstance(action, dict) or not isinstance(action.get("action_index"), int):
            raise ValueError("Expected an edit result reference")
        if field not in {"shape_id", "mask_id", "slot", "ids", "id"}:
            raise ValueError("Unsupported edit result field")
        return {"$rpy_result": [action["action_index"], field]}

    @staticmethod
    def linspace(start, end, count):
        if not isinstance(count, int) or not 1 <= count <= 256:
            raise ValueError("linspace supports 1–256 values")
        return [start] if count == 1 else [start + i * (end - start) / (count - 1) for i in range(count)]

    def draw(self, *shapes, width=512, height=512):
        return self.edit("create_shape_asset", shapes=list(shapes), width=width, height=height)

    def pitch(self, source="essentia", detail="phrases"):
        if source not in {"essentia", "rmvpe"} or detail not in {"phrases", "detail"}:
            raise ValueError("Unknown pitch source or detail")
        return deepcopy(self._snapshot.get("pitch", {}).get(source, {}).get(detail, []))

    def reference(self, key):
        if key not in self._snapshot.get("references", {}):
            raise ValueError("Include the reference query key in the script inputs")
        return deepcopy(self._snapshot["references"][key])


chart = None


def result(value):
    """Set the structured result returned by the script."""
    global _result
    _result = value


_result = None
