using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace RevelationHub;

internal sealed record Chapter(string Book,string Title,string Body);
internal static class Guide
{
    internal static readonly List<Chapter> Chapters=Read();
    private static List<Chapter> Read()
    {
        var chapters=new List<Chapter>();
        foreach(var (id,book) in new[]{("hub","Hub"),("editor","制谱器"),("modules","制谱器模块")})
        {
            using var stream=typeof(Guide).Assembly.GetManifestResourceStream("RevelationHub.guides."+id+".md");
            using var reader=new StreamReader(stream);string title="概览";var lines=new List<string>();
            void Add(){string body=string.Join("\n",lines).Trim();if(body.Length>0)chapters.Add(new(book,title,body));lines.Clear();}
            while(reader.ReadLine() is string line)
            {
                if(line.StartsWith("# "))continue;
                if(line.StartsWith("## ")){Add();title=line[3..];continue;}
                if(line.StartsWith("|") && line.All(c=>c is '|' or ' ' or '-' or ':'))continue;
                lines.Add(line.Trim('|').Replace(" | ","    ·    ").Replace("**","").Replace("`","").TrimEnd());
            }
            Add();
        }
        return chapters;
    }
}
