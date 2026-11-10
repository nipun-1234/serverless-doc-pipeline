const API = import.meta.env.VITE_API_URL;

export async function uploadFile(file) {
  const res = await fetch(`${API}/upload-url`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ filename: file.name, contentType: file.type }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || "Could not get upload URL");

  const put = await fetch(data.uploadUrl, {
    method: "PUT",
    headers: { "Content-Type": file.type },
    body: file,
  });
  if (!put.ok) throw new Error("Upload to S3 failed");
  return data.key;
}

export async function listFiles() {
  const res = await fetch(`${API}/files`);
  if (!res.ok) throw new Error("Could not load files");
  return (await res.json()).files;
}
