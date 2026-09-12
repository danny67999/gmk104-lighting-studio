using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Web.Script.Serialization;

namespace Gmk104LightingStudio
{
    public sealed class MappingEntry
    {
        public string keyId;
        public int? ledIndex;
        public bool confirmed;
        public MappingEntry() { }
        public MappingEntry(string key, int? index, bool isConfirmed) { keyId = key; ledIndex = index; confirmed = isConfirmed; }
    }

    public sealed class MappingFile
    {
        public int schemaVersion = 1;
        public string layoutId = "ansi-104";
        public int ledCount = 104;
        public List<MappingEntry> mappings = new List<MappingEntry>();

        public static MappingFile Load(string path)
        {
            var json = PersistJson.Read(path);
            var value = new MappingFile {
                schemaVersion = PersistJson.Int(json, "schemaVersion"),
                layoutId = PersistJson.String(json, "layoutId"),
                ledCount = PersistJson.Int(json, "ledCount")
            };
            foreach (var item in PersistJson.Array(json, "mappings"))
            {
                var entry = PersistJson.Object(item);
                value.mappings.Add(new MappingEntry(PersistJson.String(entry, "keyId"),
                    PersistJson.OptionalInt(entry, "ledIndex"), PersistJson.Bool(entry, "confirmed")));
            }
            value.Validate(null);
            return value;
        }

        public void Save(string path) { Validate(null); PersistJson.Save(path, this); }
        public void Save(string path, KeyGeometry[] keys) { Validate(keys); PersistJson.Save(path, this); }

        public void Validate(KeyGeometry[] keys)
        {
            PersistJson.Require(schemaVersion == 1 && layoutId == "ansi-104" && ledCount == 104, "Unsupported keyboard mapping format.");
            PersistJson.Require(mappings != null && mappings.Count == 104 && mappings.All(x => x != null && !String.IsNullOrEmpty(x.keyId)), "A mapping must contain all 104 keyboard keys.");
            var ids = new HashSet<string>(mappings.Select(x => x.keyId), StringComparer.Ordinal);
            PersistJson.Require(ids.Count == 104, "Mapping contains duplicate key identifiers.");
            if (keys != null)
                PersistJson.Require(keys.Length == 104 && keys.All(x => x != null) && ids.SetEquals(keys.Select(x => x.id)), "Mapping does not match this keyboard layout.");
            var indices = mappings.Where(x => x.ledIndex.HasValue).Select(x => x.ledIndex.Value).ToArray();
            PersistJson.Require(indices.All(x => x >= 0 && x < 104) && indices.Distinct().Count() == indices.Length, "Mapping contains duplicate or invalid LED indices.");
            PersistJson.Require(mappings.All(x => !x.confirmed || x.ledIndex.HasValue), "A confirmed key is missing its LED index.");
        }

        public void Assign(string keyId, int index)
        {
            PersistJson.Require(index >= 0 && index < 104, "LED index must be 0-103.");
            var selected = mappings.Where(x => x.keyId == keyId).ToArray();
            PersistJson.Require(selected.Length == 1, "Select a unique keyboard key.");
            foreach (var entry in mappings.Where(x => x.ledIndex == index)) { entry.ledIndex = null; entry.confirmed = false; }
            selected[0].ledIndex = index;
            selected[0].confirmed = true;
        }

        public MappingFile Clone()
        {
            return new MappingFile { schemaVersion = schemaVersion, layoutId = layoutId, ledCount = ledCount,
                mappings = mappings.Select(x => new MappingEntry(x.keyId, x.ledIndex, x.confirmed)).ToList() };
        }

        public static MappingFile RowOrder(KeyGeometry[] keys)
        {
            var result = new MappingFile { mappings = keys.OrderBy(x => x.y + x.height - 1).ThenBy(x => x.x)
                .Select((x, i) => new MappingEntry(x.id, i, true)).ToList() };
            result.Validate(keys);
            PersistJson.Require(result.mappings[0].keyId == "Escape", "Keyboard row order must begin with Escape.");
            return result;
        }
    }

    // The Mac and Windows applications share this JSON schema. Explicit field
    // parsing prevents malformed files from silently becoming default settings.
    internal static class PersistJson
    {
        internal static void Require(bool valid, string message) { if (!valid) throw new InvalidDataException(message); }
        internal static JavaScriptSerializer Serializer() { return new JavaScriptSerializer { MaxJsonLength = 1024 * 1024, RecursionLimit = 48 }; }
        internal static Dictionary<string, object> Read(string path)
        {
            Require(new FileInfo(path).Length <= 1024 * 1024, "The settings file is too large.");
            return Object(Serializer().DeserializeObject(File.ReadAllText(path)));
        }
        internal static Dictionary<string, object> Object(object value)
        {
            var result = value as Dictionary<string, object>;
            Require(result != null, "Expected a JSON object.");
            return result;
        }
        internal static object Field(Dictionary<string, object> json, string name)
        {
            object value; Require(json.TryGetValue(name, out value) && value != null, "Missing required field: " + name); return value;
        }
        internal static string String(Dictionary<string, object> json, string name)
        {
            var value = Field(json, name) as string; Require(value != null, "Invalid text field: " + name); return value;
        }
        internal static bool Bool(Dictionary<string, object> json, string name)
        {
            var value = Field(json, name); Require(value is bool, "Invalid Boolean field: " + name); return (bool)value;
        }
        internal static double Number(Dictionary<string, object> json, string name)
        {
            var value = Field(json, name);
            Require(value is int || value is long || value is decimal || value is double || value is float, "Invalid number: " + name);
            double result = Convert.ToDouble(value, CultureInfo.InvariantCulture);
            Require(!Double.IsNaN(result) && !Double.IsInfinity(result), "Invalid number: " + name); return result;
        }
        internal static int Int(Dictionary<string, object> json, string name)
        {
            var number = Number(json, name);
            Require(number >= Int32.MinValue && number <= Int32.MaxValue && number == Math.Truncate(number), "Invalid integer: " + name);
            return (int)number;
        }
        internal static int? OptionalInt(Dictionary<string, object> json, string name) { object value; return json.TryGetValue(name, out value) && value != null ? (int?)Int(json, name) : null; }
        internal static double OptionalNumber(Dictionary<string, object> json, string name, double fallback) { object value; return json.TryGetValue(name, out value) && value != null ? Number(json, name) : fallback; }
        internal static bool OptionalBool(Dictionary<string, object> json, string name, bool fallback) { object value; return json.TryGetValue(name, out value) && value != null ? Bool(json, name) : fallback; }
        internal static object[] Array(Dictionary<string, object> json, string name)
        {
            var value = Field(json, name) as object[]; Require(value != null, "Invalid list: " + name); return value;
        }
        internal static RGB Color(object value)
        {
            var json = Object(value); int r = Int(json, "r"), g = Int(json, "g"), b = Int(json, "b");
            Require(r >= 0 && r <= 255 && g >= 0 && g <= 255 && b >= 0 && b <= 255, "RGB channels must be 0-255.");
            return new RGB((byte)r, (byte)g, (byte)b);
        }
        internal static void Save(string path, object value)
        {
            var bytes = new UTF8Encoding(false).GetBytes(Serializer().Serialize(value));
            string fullPath = Path.GetFullPath(path), directory = Path.GetDirectoryName(fullPath);
            Directory.CreateDirectory(directory);
            string temporary = Path.Combine(directory, "." + Path.GetFileName(fullPath) + "." + Guid.NewGuid().ToString("N") + ".tmp");
            try
            {
                using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { stream.Write(bytes, 0, bytes.Length); stream.Flush(true); }
                // Indexers/scanners can briefly hold a newly written profile without delete sharing.
                // Retry only known transient replacement errors; never delete the original as a fallback.
                for (int attempt = 0; ; attempt++)
                {
                    try { if (File.Exists(fullPath)) File.Replace(temporary, fullPath, null); else File.Move(temporary, fullPath); break; }
                    catch (IOException error)
                    {
                        int code = error.HResult & 65535;
                        if (attempt >= 3 || !File.Exists(temporary) || (code != 32 && code != 33 && code != 1175)) throw;
                        System.Threading.Thread.Sleep(25 << attempt);
                    }
                }
            }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
        }
    }
}
