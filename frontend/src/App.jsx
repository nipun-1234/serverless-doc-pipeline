import { useCallback, useEffect, useState } from "react";
import { listFiles, uploadFile } from "./api.js";

function formatSize(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

export default function App() {
  const [files, setFiles] = useState([]);
  const [status, setStatus] = useState("");
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(async () => {
    try {
      setFiles(await listFiles());
    } catch (e) {
      setStatus(e.message);
    }
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  async function onChange(e) {
    const file = e.target.files[0];
    if (!file) return;
    setBusy(true);
    setStatus(`Uploading ${file.name}...`);
    try {
      await uploadFile(file);
      setStatus("Uploaded! Waiting for processing...");
      // Lambda usually finishes within a few seconds; poll a few times.
      for (let i = 0; i < 6; i++) {
        await new Promise((r) => setTimeout(r, 2000));
        await refresh();
      }
      setStatus("Done.");
    } catch (err) {
      setStatus(`Error: ${err.message}`);
    } finally {
      setBusy(false);
      e.target.value = "";
    }
  }

  return (
    <main className="container">
      <h1>Serverless Document Pipeline</h1>
      <p className="sub">
        Upload an image, PDF or text file. S3 triggers a Lambda that processes it and stores the
        result in DynamoDB.
      </p>

      <label className={`drop ${busy ? "disabled" : ""}`}>
        <input
          type="file"
          accept="image/jpeg,image/png,image/gif,image/webp,application/pdf,text/plain,text/markdown,text/csv"
          onChange={onChange}
          disabled={busy}
        />
        {busy ? "Working..." : "Click to choose a file"}
      </label>
      {status && <p className="status">{status}</p>}

      <div className="header-row">
        <h2>Processed files</h2>
        <button onClick={refresh}>Refresh</button>
      </div>

      {files.length === 0 && <p className="sub">Nothing here yet.</p>}

      <ul className="list">
        {files.map((f) => (
          <li key={f.id} className="card">
            {f.thumbnail_url && <img src={f.thumbnail_url} alt={f.filename} />}
            <div className="body">
              <strong>{f.filename}</strong>
              <span className={`badge ${f.status}`}>{f.status}</span>
              <div className="meta">
                {f.kind} · {formatSize(f.size)} · {new Date(f.processed_at * 1000).toLocaleString()}
              </div>
              {f.text_preview && <pre>{f.text_preview.slice(0, 400)}</pre>}
              {f.error && <div className="meta error">{f.error}</div>}
            </div>
          </li>
        ))}
      </ul>
    </main>
  );
}
