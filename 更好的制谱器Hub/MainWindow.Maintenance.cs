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
    private void AddMaintenanceButtons(StackPanel panel,Release r,Release latest,CudaSupport cuda)
    {
        var row=Actions(panel);
        if(latest!=null) row.Children.Add(ActionButton("更新到 v"+latest.version,()=>_ = ChangeVersion(r,latest)));
        row.Children.Add(ActionButton("校验文件",()=>_ = RunJob(async (p,ct)=>{
            var bad=await library.Verify(r,p,ct);
            return bad.Count==0?"v"+r.version+" 的发行文件完整。":$"发现 {bad.Count} 个缺失或损坏文件：{string.Join("、",bad.Take(4).Select(Path.GetFileName))}。可点击「修复」。";
        })));
        if(r.size>0) row.Children.Add(ActionButton("修复",()=>_ = ChangeVersion(r,r)));
        if (cuda != null)
        {
            var button = ActionButton(cuda.Installed ? "卸载 CUDA 支持" : "添加 CUDA 支持", () => {
                if (cuda.Installed && !Confirm($"卸载 v{r.version} 的 CUDA 附加包？下次分析将使用 CPU。")) return;
                _ = RunJob(async (progress,ct) => {
                    await Task.Run(() => library.ChangeCuda(r.version,!cuda.Installed,progress,ct),ct);
                    return cuda.Installed ? "CUDA 支持已卸载。" : "CUDA 支持已安装，下次分析将自动检测显卡。";
                }, Render);
            });
            button.ToolTip = $"ONNX 模型推理 · 附加包 {cuda.Size / 1048576.0:F0} MiB";
            row.Children.Add(button);
        }
        row.Children.Add(ActionButton("删除版本",()=> {
            if(download!=null || !Confirm($"将 v{r.version} 的安装目录（含放入该目录的文件）移到回收站？"))return;
            _=RunJob(async (_,ct)=>{await Task.Run(()=>library.RemoveVersion(r.version),ct);return "版本已移到回收站。";},Render);
        }));
    }
    private Task ChangeVersion(Release from,Release to) => RunJob(async(p,ct)=>{
        await Task.Run(()=>library.Update(from,to,p,ct,options.Incremental),ct);
        return from.version==to.version?"已修复 v"+to.version+"。":$"已在原安装位置更新到 v{to.version}。";
    },Render);
    private async Task RunJob(Func<IProgress<Transfer>,CancellationToken,Task<string>> work,Action changed=null)
    {
        if(download!=null){Message("请等待当前任务完成，或先取消。");return;}
        download=CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
        var job=download;UpdateDialogAction();
        RefreshEditorActions();
        SetProgress(JobProgress,0);
        Transfer latest=new("处理中…");
        bool showing=false;
        async Task Reveal()
        {
            await Task.Delay(250);
            if (download!=job) return;
            showing=true;ShowTransfer(latest);
        }
        _=Reveal();
        var progress=new Progress<Transfer>(t=>{if(download!=job)return;latest=t;if(showing)ShowTransfer(t);});
        string result; bool failed=false;
        try{result=await work(progress,job.Token);}
        catch(OperationCanceledException){result="已取消。";}
        catch(Exception ex){result=ex.Message;failed=true;}
        finally{download=null;job.Dispose();ShowTransfer(hubTransfer);UpdateDialogAction();RefreshEditorActions();}
        if(closing){Close();return;}
        try {changed?.Invoke();}catch(Exception ex){result=ex.Message;failed=true;}
        Message(result,failed);
    }
}
