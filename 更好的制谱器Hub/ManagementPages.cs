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
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace RevelationHub;

public partial class MainWindow
{
    private readonly EditorProfile profile=new(EditorProfile.DefaultRoot);
    private readonly EditorModels models;
    private HubOptions options;
    private string page="版本库";
    private string configFile=EditorProfile.Prefs;
    private bool OnLibrary => page is "版本库" or "已安装";
    internal bool AnimateControls => options?.Animations==true && SystemParameters.ClientAreaAnimation;
    private void NavigateClick(object sender,RoutedEventArgs e) => Navigate((string)((Button)sender).Content);
    private void CancelJob(object sender,RoutedEventArgs e) => download?.Cancel();
    private void Navigate(string dest)
    {
        page=dest;
        onlyInstalled=dest=="已安装";
        LibraryBody.Visibility=CatalogStatus.Visibility=OnLibrary?Visibility.Visible:Visibility.Collapsed;
        ManagerBody.Visibility=OnLibrary?Visibility.Collapsed:Visibility.Visible;
        RefreshButton.Content=OnLibrary?"刷新版本":"刷新";
        foreach(var b in Navigation.Children.OfType<Button>()) b.Background=ColorOf(Equals(b.Content,page)?"#353A42":"#191D22");
        PageTitle.Text=page;EmptyState.Text="";
        if(download==null) JobPanel.Visibility=Visibility.Collapsed;
        Manager.Children.Clear();ManagerBody.ScrollToHome();
        try
        {
            if(OnLibrary){Render();ShowNotices();LibraryBody.ScrollToHome();}
            else switch(dest)
            {
                case "模型管理": ModelPage();break;
                case "编辑器配置": ConfigPage();break;
                case "参考工程": ReferencePage();break;
                case "使用文档": GuidePage();break;
                case "Hub 设置": SettingsPage();break;
            }
        }
        catch(Exception ex) { Message(ex.Message); }
        if(options.Animations && SystemParameters.ClientAreaAnimation)
        {
            var view=OnLibrary?LibraryBody:ManagerBody;
            var t=new TranslateTransform();view.RenderTransform=t;
            var duration=TimeSpan.FromMilliseconds(220);
            t.BeginAnimation(TranslateTransform.YProperty,new DoubleAnimation(12,0,duration){EasingFunction=new CubicEase{EasingMode=EasingMode.EaseOut}});
            view.BeginAnimation(OpacityProperty,new DoubleAnimation(.45,1,duration){EasingFunction=new QuadraticEase{EasingMode=EasingMode.EaseOut}});
        }
    }
    private void Message(string text) {JobPanel.Visibility=Visibility.Visible;JobStatus.Text=text;JobProgress.Visibility=JobCancel.Visibility=Visibility.Collapsed;}
    private static Button ActionButton(string name,Action action)
    {
        var b=new Button{Content=name,Margin=new Thickness(0,3,6,3),Padding=new Thickness(12,6,12,6)};
        b.Click+=(_,_)=>action();return b;
    }
    private void Act(Action work) {try{work();}catch(Exception ex){Message(ex.Message);}}
    private bool Confirm(string text) => MessageBox.Show(this,text,"更好的制谱器 Hub",MessageBoxButton.YesNo,MessageBoxImage.Question,MessageBoxResult.No)==MessageBoxResult.Yes;
    private static void OpenPath(string path) => Process.Start(new ProcessStartInfo(path){UseShellExecute=true});
    private void Heading(string text)
    {
        var label=Label(text,19,"#F1F3F5");label.FontWeight=FontWeights.SemiBold;label.Margin=new Thickness(0,12,0,5);Manager.Children.Add(label);
    }
    private void Detail(string text) => Manager.Children.Add(Label(text,13,"#B4BFCD"));
    private WrapPanel Actions(Panel panel){var row=new WrapPanel{Margin=new Thickness(0,5,0,8)};panel.Children.Add(row);return row;}
    private void AddMaintenanceButtons(StackPanel panel,Release r)
    {
        var row=Actions(panel);
        var latest=available.FirstOrDefault(x=>Version.Parse(x.version)>Version.Parse(r.version) && !library.LocalVersions().Contains(x.version));
        if(latest!=null) row.Children.Add(ActionButton("更新到 v"+latest.version,()=>_ = ChangeVersion(r,latest)));
        row.Children.Add(ActionButton("校验文件",()=>_ = RunJob(async (p,ct)=>{
            var bad=await library.Verify(r,p,ct);
            return bad.Count==0?"v"+r.version+" 的发行文件完整。":$"发现 {bad.Count} 个缺失或损坏文件：{string.Join("、",bad.Take(4).Select(Path.GetFileName))}。可点击「修复」。";
        })));
        if(r.size>0) row.Children.Add(ActionButton("修复",()=>_ = ChangeVersion(r,r)));
        row.Children.Add(ActionButton("删除版本",()=> {
            if(download!=null || !Confirm($"将 v{r.version} 的安装目录（含放入该目录的文件）移到回收站？"))return;
            _=RunJob(async (_,ct)=>{await Task.Run(()=>library.RemoveVersion(r.version),ct);return "版本已移到回收站。";});
        }));
    }
    private Task ChangeVersion(Release from,Release to) => RunJob(async(p,ct)=>{
        await Task.Run(()=>library.Update(from,to,p,ct,options.Incremental),ct);
        return from.version==to.version?"已修复 v"+to.version+"。":$"已在原安装位置更新到 v{to.version}。";
    });
    private async Task RunJob(Func<IProgress<Transfer>,CancellationToken,Task<string>> work)
    {
        if(download!=null){MessageBox.Show(this,"请等待当前任务完成，或先取消。","更好的制谱器 Hub");return;}
        download=CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
        var job=download;ApplyButton.IsEnabled=false;
        JobPanel.Visibility=JobCancel.Visibility=JobProgress.Visibility=Visibility.Visible;
        JobProgress.IsIndeterminate=true;JobStatus.Text="正在准备…";
        var progress=new Progress<Transfer>(t=>{
            if(download!=job)return;
            JobStatus.Text=t.Stage+(t.Total>0?$"  {100.0*t.Bytes/t.Total:F0}%":"");
            JobProgress.IsIndeterminate=t.Total<=0;
            if(t.Total>0) JobProgress.Value=100.0*t.Bytes/t.Total;
        });
        string result;
        try{result=await work(progress,job.Token);}
        catch(OperationCanceledException){result="已取消。";}
        catch(Exception ex){result=ex.Message;}
        finally{download=null;job.Dispose();ApplyButton.IsEnabled=true;}
        if(closing){Close();return;}
        if(OnLibrary)Render();else if(page=="模型管理")Navigate(page);
        Message(result);
    }
    private void ModelPage()
    {
        foreach(var (id,name) in new[]{("music2emo","Music2Emo · 情绪分析"),("madmom","madmom · 节拍与起音")})
        {
            Heading(name);Detail($"{models.Count(id)} / {models.Files(id).Length} 个模型及配套文件");
            Detail(models.Location(id));
            var row=Actions(Manager);
            row.Children.Add(ActionButton("下载或补齐",()=>_ = RunJob(async(p,ct)=>{await models.Install(id,p,ct);return name+" 已就绪。";})));
            row.Children.Add(ActionButton("校验",()=>_ = RunJob(async(_,ct)=>{var bad=await Task.Run(()=>models.Verify(id,ct),ct);return bad.Count==0?"模型文件完整。":$"{bad.Count} 个文件需要补齐：{string.Join("、",bad.Take(3))}";})));
            row.Children.Add(ActionButton("打开目录",()=>Act(()=>OpenPath(models.Location(id)))));
            row.Children.Add(ActionButton("移除模型",()=>{if(!Confirm("移除 "+name+" 的已知模型文件？"))return;_=RunJob(async(_,ct)=>{await Task.Run(()=>models.Remove(id),ct);return "已移除模型文件。";});}));
        }
        Heading("随编辑器安装的模型");Detail("Beat This! 等随版本分发的模型可在「已安装 → 校验文件」中检查或修复。");
    }
    private void ConfigPage()
    {
        var selector=Actions(Manager);
        foreach(var (file,label) in new[]{(EditorProfile.Prefs,"偏好设置"),(EditorProfile.Agent,"Agent"),(EditorProfile.Mcp,"MCP")})
        {
            var b=ActionButton(label,()=>{configFile=file;Navigate(page);});b.IsEnabled=file!=configFile;selector.Children.Add(b);
        }
        Detail(Path.Combine(profile.Root,configFile));
        Detail("关闭编辑器后保存，下次打开编辑器时生效。");
        var doc=profile.Config(configFile);var values=new Dictionary<Setting,Func<string>>();
        foreach(var f in EditorProfile.Fields.Where(f=>f.File==configFile))
        {
            string value=doc.Get(f);var label=Label(f.Label,14,"#E1E5EA");label.Margin=new Thickness(0,10,0,3);Manager.Children.Add(label);
            if(f.Kind=="bool"){var chk=Toggle(f.Label,value=="true");Manager.Children.Add(chk);label.Visibility=Visibility.Collapsed;values[f]=()=>chk.IsChecked==true?"true":"false";}
            else if(f.Kind=="secret"){var box=new PasswordBox{Password=value,Padding=new Thickness(7)};Manager.Children.Add(box);values[f]=()=>box.Password;}
            else if(f.Kind.Contains('|')){var box=new ComboBox{ItemsSource=f.Kind.Split('|'),SelectedItem=value,MinHeight=29};Manager.Children.Add(box);values[f]=()=>box.SelectedItem?.ToString()??value;}
            else {var box=new TextBox{Text=value,Padding=new Thickness(7)};Manager.Children.Add(box);values[f]=()=>box.Text;}
        }
        Actions(Manager).Children.Add(ActionButton("保存配置",()=>Act(()=>{
            var changes=values.ToDictionary(v=>v.Key,v=>v.Value()).Where(kv=>kv.Value!=doc.Get(kv.Key)).ToDictionary();
            if(changes.Count>0) doc.Save(changes);
            Message(changes.Count>0?"配置已保存。":"配置未变更。");
        })));
    }
    private static CheckBox Toggle(string label,bool enabled) => new(){Content=label,IsChecked=enabled,Foreground=ColorOf("#E2E7ED"),Margin=new Thickness(0,7,0,7)};
    private void SettingsPage()
    {
        Heading("下载与更新");
        var inc=Toggle("优先使用增量包更新编辑器",options.Incremental);
        var auto=Toggle("自动检查并下载 Hub 更新",options.AutoUpdates);
        Manager.Children.Add(inc);Manager.Children.Add(auto);
        Heading("界面");
        var notices=Toggle("在版本库显示发行公告",options.Announcements);
        var motion=Toggle("启用界面缓动动画",options.Animations);
        Manager.Children.Add(notices);Manager.Children.Add(motion);
        Detail("Windows 关闭动画时，Hub 也会关闭页面过渡。");
        Actions(Manager).Children.Add(ActionButton("保存设置",()=>Act(()=>{
            var updated=new HubOptions(motion.IsChecked==true,inc.IsChecked==true,notices.IsChecked==true,auto.IsChecked==true);
            updated.Save(library.Root);options=updated;ShowNotices();_=CheckServices(false);Message("Hub 设置已保存。");
        })));
    }
    private void ReferencePage()
    {
        var actions=Actions(Manager);
        actions.Children.Add(ActionButton("导入参考谱",()=>Act(()=>{
            var dlg=new OpenFileDialog{Filter="谱面 JSON 或 ZIP|*.json;*.zip"};if(dlg.ShowDialog(this)!=true)return;
            profile.ImportReference(dlg.FileName);Navigate(page);Message("已导入参考谱数据。");
        })));
        actions.Children.Add(ActionButton("打开参考库目录",()=>Act(()=>{Directory.CreateDirectory(profile.References);OpenPath(profile.References);})));
        Detail("这里的本地参考工程也可在编辑器的脚本、Agent 和 MCP 参考库中使用。");
        Heading("内置乐句示例");Detail("随编辑器提供，可在编辑器中查询音符、事件与关键帧。");
        foreach(var item in profile.ListReferences())
        {
            Heading(item.Title);Detail($"{item.Difficulty}   ·   {item.Items} 条谱面数据"+(item.Media?"   ·   含素材包":""));
            var row=Actions(Manager);
            row.Children.Add(ActionButton("导出 JSON",()=>Act(()=>{var d=new SaveFileDialog{Filter="谱面 JSON|*.json",FileName=item.Id+".json"};if(d.ShowDialog(this)==true)File.Copy(profile.ReferenceFile(item.Id),d.FileName,true);})));
            row.Children.Add(ActionButton("删除",()=>Act(()=>{if(!Confirm("删除该参考工程、素材授权和参考库内的素材副本？"))return;profile.RemoveReference(item.Id);Navigate(page);})));
        }
    }
    private void GuidePage()
    {
        var search=new TextBox{Padding=new Thickness(9),Margin=new Thickness(0,3,0,12)};
        System.Windows.Automation.AutomationProperties.SetName(search,"搜索使用文档");
        Detail("搜索模块、菜单名称或操作");Manager.Children.Add(search);
        var results=new StackPanel();Manager.Children.Add(results);
        void Filter()
        {
            results.Children.Clear();
            var terms=search.Text.Split(' ',StringSplitOptions.RemoveEmptyEntries|StringSplitOptions.TrimEntries);
            foreach(var chapter in Guide.Chapters.Where(c=>terms.All(t=>(c.Book+c.Title+c.Body).Contains(t,StringComparison.OrdinalIgnoreCase))))
            {
                var content=Label(chapter.Body,14,"#D6DEE8");content.Margin=new Thickness(12,6,6,12);
                var exp=new Expander{Header=chapter.Book+"   /   "+chapter.Title,Foreground=ColorOf("#E5EAF1"),Content=content,Margin=new Thickness(0,3,0,3),IsExpanded=terms.Length>0};
                results.Children.Add(exp);
            }
            if(results.Children.Count==0)results.Children.Add(Label("没有匹配章节。可尝试「黄键」「更新」或「MCP」。",14,"#CCD3DC"));
        }
        search.TextChanged+=(_,_)=>Filter();Filter();
    }
}

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
