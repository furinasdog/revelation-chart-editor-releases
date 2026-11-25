using Microsoft.Win32;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace RevelationHub;

public partial class MainWindow
{
    private void ReferencePage()
    {
        Heading("本地参考库");
        var actions=Actions(Manager);
        actions.Children.Add(ActionButton("导入参考谱",()=>Act(()=>{
            var dlg=new OpenFileDialog{Filter="谱面 JSON 或 ZIP|*.json;*.zip"};if(dlg.ShowDialog(this)!=true)return;
            profile.ImportReference(dlg.FileName);Navigate(page,true);Message("已导入参考谱数据。");
        })));
        actions.Children.Add(ActionButton("打开参考库目录",()=>Act(()=>{Directory.CreateDirectory(profile.References);OpenPath(profile.References);})));
        Detail("这里的本地参考工程也可在编辑器的脚本、Agent 和 MCP 参考库中使用。");
        Heading("内置乐句示例");Detail("随编辑器提供，可在编辑器中查询音符、事件与关键帧。");
        foreach(var item in profile.ListReferences())
        {
            Heading(item.Title);Detail($"{item.Difficulty}   ·   {item.Items} 条谱面数据"+(item.Media?"   ·   含素材包":""));
            var row=Actions(Manager);
            row.Children.Add(ActionButton("导出 JSON",()=>Act(()=>{var d=new SaveFileDialog{Filter="谱面 JSON|*.json",FileName=item.Id+".json"};if(d.ShowDialog(this)==true)File.Copy(profile.ReferenceFile(item.Id),d.FileName,true);})));
            row.Children.Add(ActionButton("删除",()=>Act(()=>{if(!Confirm("删除该参考工程、素材授权和参考库内的素材副本？"))return;profile.RemoveReference(item.Id);Navigate(page,true);})));
        }
    }
    private void GuidePage()
    {
        Heading("搜索文档");
        var search=new TextBox{Margin=new Thickness(0,5,0,1)};
        System.Windows.Automation.AutomationProperties.SetName(search,"搜索使用文档");
        Detail("搜索模块、菜单名称或操作");section.Children.Add(search);
        Heading("使用手册");
        var results=new StackPanel();section.Children.Add(results);
        void Filter()
        {
            results.Children.Clear();
            var terms=search.Text.Split(' ',StringSplitOptions.RemoveEmptyEntries|StringSplitOptions.TrimEntries);
            foreach(var chapter in Guide.Chapters.Where(c=>terms.All(t=>(c.Book+c.Title+c.Body).Contains(t,StringComparison.OrdinalIgnoreCase))))
            {
                var content=Label(chapter.Body,14,"Ink");content.Margin=new Thickness(12,6,6,12);
                var exp=new Expander{Header=chapter.Book+"   /   "+chapter.Title,Content=content,Margin=new Thickness(0,3,0,3),IsExpanded=terms.Length>0};
                results.Children.Add(exp);
            }
            if(results.Children.Count==0)results.Children.Add(Label("没有匹配章节。可尝试「黄键」「更新」或「MCP」。",14,"Muted"));
        }
        search.TextChanged+=(_,_)=>Filter();Filter();
    }
}
