import os, requests, json, hashlib
from supabase import create_client

URL=os.environ["SUPABASE_URL"]
KEY=os.environ["SUPABASE_SERVICE_ROLE_KEY"]
db=create_client(URL, KEY)

def save(item):
    item["id"]=item.get("id") or hashlib.sha1((item["source"]+item["title"]).encode()).hexdigest()
    db.table("content").upsert(item).execute()

def jikan():
    page=1
    while page<=3:
        data=requests.get(f"https://api.jikan.moe/v4/top/anime?page={page}",timeout=30).json()
        for a in data.get("data",[]):
            save({"title":a.get("title") or "Untitled","content_type":"anime",
              "synopsis":a.get("synopsis"),"poster_url":(a.get("images",{}).get("jpg",{}) or {}).get("image_url"),
              "release_year":(a.get("year") or None),"rating":a.get("score"),
              "source":"Jikan","source_url":a.get("url")})
        page+=1

def tvmaze():
    for page in range(3):
        r=requests.get(f"https://api.tvmaze.com/shows?page={page}",timeout=30)
        if r.status_code==404: break
        for s in r.json():
            image=s.get("image") or {}
            premiered=s.get("premiered") or ""
            save({"title":s.get("name") or "Untitled","content_type":"series",
              "synopsis":s.get("summary"),"poster_url":image.get("medium"),
              "release_year":int(premiered[:4]) if premiered[:4].isdigit() else None,
              "rating":(s.get("rating") or {}).get("average"),
              "source":"TVmaze","source_url":s.get("url")})

def archive():
    params={"q":"mediatype:movies AND collection:feature_films","fl[]":["identifier","title","description","year"],"rows":100,"output":"json"}
    data=requests.get("https://archive.org/advancedsearch.php",params=params,timeout=60).json()
    for d in data.get("response",{}).get("docs",[]):
        ident=d.get("identifier")
        save({"title":d.get("title") or ident,"content_type":"movie",
          "synopsis":d.get("description") if isinstance(d.get("description"),str) else None,
          "release_year":int(d["year"]) if str(d.get("year","")).isdigit() else None,
          "source":"Internet Archive","source_url":"https://archive.org/details/"+ident})

if __name__=="__main__":
    jikan(); tvmaze(); archive()
