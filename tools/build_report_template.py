# -*- coding: utf-8 -*-
"""按赛方模板生成作品报告（短版）：封面 + 摘要 + 五部分 + 照片占位。

运行： python -I report_figs/build_report_template.py
输出： docs/作品报告_43798.docx
"""
import os
from docx import Document
from docx.shared import Pt, Cm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
FIGS = 'report_figs'
OUT = os.path.join('docs', '作品报告_43798.docx')

CN, CN_H, EN = '宋体', '黑体', 'Times New Roman'
doc = Document()

sec = doc.sections[0]
sec.page_width, sec.page_height = Cm(21.0), Cm(29.7)
sec.top_margin = sec.bottom_margin = Cm(2.3)
sec.left_margin = sec.right_margin = Cm(2.5)

normal = doc.styles['Normal']
normal.font.name = EN
normal.font.size = Pt(10.5)
normal.element.rPr.rFonts.set(qn('w:eastAsia'), CN)
normal.paragraph_format.line_spacing = 1.4
normal.paragraph_format.space_before = Pt(0)
normal.paragraph_format.space_after = Pt(0)


def set_run(run, cn=CN, en=EN, size=10.5, bold=False, color=None):
    run.font.name = en
    run.font.size = Pt(size)
    run.font.bold = bold
    if color:
        run.font.color.rgb = color
    rPr = run._element.get_or_add_rPr()
    rFonts = rPr.find(qn('w:rFonts'))
    if rFonts is None:
        rFonts = OxmlElement('w:rFonts')
        rPr.append(rFonts)
    rFonts.set(qn('w:eastAsia'), cn)
    rFonts.set(qn('w:ascii'), en)
    rFonts.set(qn('w:hAnsi'), en)


def para(text='', indent=True, align='justify', size=10.5, bold=False,
         before=0, after=0, cn=CN, line=1.4):
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.line_spacing = line
    pf.space_before = Pt(before)
    pf.space_after = Pt(after)
    if indent:
        pf.first_line_indent = Pt(size * 2)
    pf.alignment = {'justify': WD_ALIGN_PARAGRAPH.JUSTIFY,
                    'center': WD_ALIGN_PARAGRAPH.CENTER,
                    'left': WD_ALIGN_PARAGRAPH.LEFT}[align]
    if text:
        set_run(p.add_run(text), cn=cn, en=EN, size=size, bold=bold)
    return p


def h(text, level=1):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(10 if level == 1 else 6)
    p.paragraph_format.space_after = Pt(4 if level == 1 else 2)
    p.paragraph_format.first_line_indent = Pt(0)
    p.paragraph_format.keep_with_next = True
    size = {1: 14, 2: 12, 3: 10.5}[level]
    set_run(p.add_run(text), cn=CN_H, size=size, bold=True)
    return p


def _dash_cell(cell, label, tip, h_cm):
    tcPr = cell._tc.get_or_add_tcPr()
    borders = OxmlElement('w:tcBorders')
    for edge in ('top', 'left', 'bottom', 'right'):
        e = OxmlElement('w:%s' % edge)
        e.set(qn('w:val'), 'dashed')
        e.set(qn('w:sz'), '8')
        e.set(qn('w:color'), 'A0A0A0')
        borders.append(e)
    tcPr.append(borders)
    shd = OxmlElement('w:shd')
    shd.set(qn('w:val'), 'clear')
    shd.set(qn('w:fill'), 'F7F7F7')
    tcPr.append(shd)
    p = cell.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(h_cm * 2.6)
    p.paragraph_format.line_spacing = 1.2
    set_run(p.add_run(label), size=9, bold=True, color=RGBColor(0x70, 0x70, 0x70))
    p2 = cell.add_paragraph()
    p2.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p2.paragraph_format.line_spacing = 1.2
    set_run(p2.add_run(tip), size=8, color=RGBColor(0x90, 0x90, 0x90))


def photo(width_cm, height_cm, label, tip):
    t = doc.add_table(rows=1, cols=1)
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.rows[0].height = Cm(height_cm)
    cell = t.rows[0].cells[0]
    cell.width = Cm(width_cm)
    _dash_cell(cell, label, tip, height_cm)
    para('', indent=False, size=4, line=1.0)


def photo_pair(l1, t1, l2, t2, height_cm=5.0, width_cm=7.6):
    t = doc.add_table(rows=1, cols=2)
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.rows[0].height = Cm(height_cm)
    for cell, l, tip in ((t.rows[0].cells[0], l1, t1), (t.rows[0].cells[1], l2, t2)):
        cell.width = Cm(width_cm)
        _dash_cell(cell, l, tip, height_cm)
    para('', indent=False, size=4, line=1.0)


def figure(path, text, width=14.5):
    p = doc.add_paragraph()
    p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.first_line_indent = Pt(0)
    p.paragraph_format.space_before = Pt(4)
    p.add_run().add_picture(os.path.join(FIGS, path), width=Cm(width))
    c = para(text, indent=False, align='center', size=9, bold=True, before=2, after=6)
    return c


def table(headers, rows, text, widths=None, size=8.5):
    para(text, indent=False, align='center', size=9, bold=True, before=6, after=2)
    t = doc.add_table(rows=1, cols=len(headers))
    t.style = 'Table Grid'
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    trPr = t.rows[0]._tr.get_or_add_trPr()
    trPr.append(OxmlElement('w:tblHeader'))
    for i, hh in enumerate(headers):
        c = t.rows[0].cells[i]
        c.text = ''
        p = c.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.line_spacing = 1.0
        set_run(p.add_run(hh), size=size, bold=True)
    for row in rows:
        cells = t.add_row().cells
        for i, v in enumerate(row):
            cells[i].text = ''
            p = cells[i].paragraphs[0]
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER if i else WD_ALIGN_PARAGRAPH.LEFT
            p.paragraph_format.line_spacing = 1.0
            set_run(p.add_run(str(v)), size=size)
    if widths:
        tot = sum(widths)
        if tot > 15.5:
            widths = [w * 15.5 / tot for w in widths]
        for i, w in enumerate(widths):
            for r in t.rows:
                r.cells[i].width = Cm(w)
    para('', indent=False, size=4, line=1.0)
    return t


def brk():
    doc.add_page_break()

# ================================================================ 封面
for _ in range(4):
    para('', indent=False, line=1.0)
para('2026 年全国大学生嵌入式芯片与系统设计竞赛', indent=False, align='center', size=13,
     cn=CN_H, after=4)
para('FPGA 赛道 · 选题一', indent=False, align='center', size=13, cn=CN_H, after=48)
para('云衡实时姿态控制系统', indent=False, align='center', size=26, bold=True, cn=CN_H, after=8)
para('—— 基于高云 GW2A-55 FPGA 的旋转倒立摆', indent=False, align='center', size=13, cn=CN_H, after=60)
for _ in range(8):
    para('', indent=False, line=1.0)
para('参赛队编号：43798', indent=False, align='center', size=14, cn=CN_H)
para('', indent=False, line=1.0)
para('2026 年 10 月', indent=False, align='center', size=12)
brk()

# ================================================================ 摘要
para('摘　要', indent=False, align='center', size=15, bold=True, cn=CN_H, before=4, after=8)
ABS = [
 '本作品以高云 GW2A-LV55PG484C8/I7 FPGA 为核心，实现 J280 旋转倒立摆的全数字控制。'
 '系统工作在 50 MHz 单时钟域，1 ms 控制节拍由硬件计数器分频得到；摆杆角度由 10 位并行 ADC'
 '（5 MHz 采样、128 点均值）读取电位器，旋臂角度由增量编码器四倍频计数。控制律全部以 Verilog '
 'RTL 实现：两路一阶常速度跟踪器给出角速度估计，四状态 LQR 反馈律输出电压指令，一级双二阶陷波器'
 '抑制 8–18 Hz 机械谐振，输出级完成限幅、压摆与占空比映射；起摆段采用能量泵，配 ±145° 软限位'
 '与臂速阻尼，接管前经角度、角速度、连续拍数三重捕获门。',
 '针对套件静摩擦大的特点（起动占空比中位 274‰，满量程仅 500‰），参数按"机械—臂速增益—观测器'
 '带宽—陷波"的顺序整定，每版至少两跑。定版三次 30 s 长跑：旋臂峰峰 15.7°、15.7°、17.7°，'
 '摆角 RMS 1.60°、1.56°、2.15°，占空比指令标准差 73‰、59‰、92‰，三次均无触轨；'
 '与旧交付版同一口径下的最好一次（32.5°、3.38°、149‰）相比，三项分别下降约 50%、50%、55%。',
 '拓展功能包括三点点位（0°/+30°/+60°）、整圈旋转与跌倒自动重起：整圈旋转 30 s 内累计 385°，'
 '恒速段 21.0°/s，摆角最大 9.5°；摆杆超过 40° 立即切断输出，垂下稳定 1.5 s 后自动重新起摆。',
 '工程实现上，闭环共 16 个 Verilog 模块，综合后 SETUP 余量 +1.284 ns，逻辑占用 31%、'
 '寄存器 25%、DSP 88%、BSRAM 70%。',
]
for t in ABS:
    para(t)
print('摘要字数', sum(len(t) for t in ABS))

brk()
# ================================================================ 第一部分
h('第一部分　作品概述', 1)

h('1.1　功能与特性', 2)
P11 = ('（1）自动起摆：摆杆从悬垂出发，能量泵按能量误差符号推动旋臂，越顶后由捕获门接管，'
       '全程不需要人工扶杆。（2）全状态平衡：1 kHz 闭环、四状态 LQR 反馈，稳态摆角 RMS 1.6°、'
       '旋臂峰峰 16° 左右。（3）抗扰：手推摆杆或旋臂后能自行回正，偏角超过 12° 时臂速增益自动'
       '降低以加快跟随。（4）点位：SW1 循环切换 0°/+30°/+60°，参考按 10°/s 平滑移动，'
       '摆杆全程直立。（5）整圈旋转：参考以 21°/s 连续前进，走满 360° 就地重锚，不反转退回。'
       '（6）跌倒自恢复：摆杆超过 40° 立即切断输出，垂下稳定 1.5 s 后自动重新起摆。'
       '（7）数据记录：896 bit × 2048 条轨迹缓冲，串口回传后可离线复算整条控制链。'
       '（8）人机接口：SW1 零点标定、SW3 启停，串口状态帧显示角度与故障码。')
para(P11)
print('1.1字数', len(P11))

h('1.2　应用领域', 2)
P12 = ('旋转倒立摆是欠驱动、开环不稳定、强摩擦对象的典型代表，其控制结构与两轮自平衡车、'
       '云台与姿态稳定、欠驱动机械臂、垂直起降飞行器的姿态段等问题同构。本作品把采样、状态估计、'
       '反馈运算、滤波与输出全部放在 FPGA 内实现，节拍由硬件确定、通道并行采集，适合对采样同步性、'
       '多传感器并行接口与长期运行可靠性有要求的场合，例如高速伺服平台的嵌入式控制器、'
       '教学实验平台，以及需要在一个芯片内同时完成多路信号调理与控制律运算的工业仪表。'
       '作品中的整定方法与故障分级策略也可直接迁移到同类欠驱动系统的工程调试。')
para(P12)
print('1.2字数', len(P12))

h('1.3　主要技术特点', 2)
P13 = ('（1）全硬件控制链路：采样、估计、反馈、滤波、输出均为 RTL 流水实现，单次控制运算约 120 个'
       '系统时钟（2.4 μs），相对 1 ms 节拍余量约 400 倍，节拍抖动只有一个时钟周期。'
       '（2）定点运算贯穿全链：角度 Q16、增益 Q8、观测器系数 Q20、陷波系数 Q28，无浮点单元。'
       '（3）状态估计用两路常速度跟踪器，BD 全零，观测器只由测量误差驱动，不依赖电机参数与摩擦模型，'
       '带宽可独立整定。（4）陷波器由 RTL 定点系数直接决定，中心 12.5 Hz、带宽 12 Hz、深度 0.6，'
       '覆盖 8–18 Hz；实测三个频带的占空比能量同时下降。（5）保护分级：软限位、通信看门狗、'
       '输出溢出、大角度切断，故障码中仅越界与跌倒允许自动恢复，其余锁存，避免自动重试掩盖硬件问题。')
para(P13)
print('1.3字数', len(P13))

h('1.4　主要性能指标', 2)
table(['指标', '数值', '测试条件'], [
    ['控制周期 / 系统时钟', '1 ms / 50 MHz', '硬件计数分频'],
    ['旋臂摆幅（峰峰）', '15.7 / 15.7 / 17.7°', '三次 30 s 长跑，10–30 s 窗口'],
    ['摆角 RMS', '1.60 / 1.56 / 2.15°', '同上'],
    ['占空比指令标准差', '73 / 59 / 92‰', '同上'],
    ['触轨 / 滑脱', '0% / 0 次', '同上'],
    ['整圈旋转', '385° / 21.0°/s / |θ|≤9.5°', '30 s 记录'],
    ['跌倒恢复', '40° 切断，1.5 s 后重起', '现场多次验证'],
    ['时序 / 资源', 'SETUP +1.284 ns；逻辑 31%、DSP 88%', 'V1.9.12.03 综合结果'],
], '表 1　主要性能指标', widths=[5.4, 6.6, 3.6])

h('1.5　主要创新点', 2)
P15 = ('（1）阈值由实测确定：捕获门与降增益门限用与实时信号同口径的 1 kHz 统计，'
       '不用抽稀数据外推。（2）机械整定先于参数整定：调平与复紧改变的是摆幅—抖动曲线的位置。'
       '（3）观测器带宽作为抖动的主旋钮：在噪声进入反馈律前滤除，而非靠陷波搬移频带能量。'
       '（4）跌倒时切断而非追摆：40° 断输出使落点可预测，避免旋臂撞限位。')
para(P15)
print('1.5字数', len(P15))

h('1.6　设计流程', 2)
P16 = ('需求分析 → 离线建模（零阶保持离散化，离散 Riccati 方程求增益初值）→ RTL 实现（定点格式'
       '与流水划分）→ 仿真验证（iverilog 状态机冒烟用例）→ 上板整定（机械、增益、观测器、陷波'
       '逐项，单变量、至少两跑）→ 数据复算（统一口径统计，回归到参数表）。')
para(P16)
print('1.6字数', len(P16))

brk()
# ================================================================ 第二部分
h('第二部分　系统组成及功能说明', 1)

h('2.1　整体介绍', 2)
para('系统由 J280 机械本体、GW2A-55 核心板、TB6612 驱动板、12 V 电源与上位机五部分组成，'
     '控制回路完全在 FPGA 内闭环，上位机只负责显示与数据回传。图 1 给出总体框图，'
     '数据流是一个闭环：传感器（电位器、编码器）→ c_adc / c_encoder → c_sensor 解算角度并'
     '做状态估计 → c_control 完成状态机与反馈运算 → c_output 限幅与压摆 → c_pwm 输出 20 kHz '
     '占空比 → TB6612 驱动电机 → 机械本体运动 → 传感器再次采样。c_swing 在起摆状态接管输出，'
     'c_trace 在后台把每个节拍的关键量写入环形缓冲，c_keys 处理零点标定与启停。')
figure('fig1_system.png', '图 1　系统总体框图', 14.8)
table(['模块', '职责', '关键接口'], [
    ['c_adc / c_encoder', '10 位并行 ADC 128 点均值；正交解码四倍频', 'raw12、count'],
    ['c_sensor', '角度换算、参考生成、两路常速度跟踪器', 'θ、a、v_a、ω_θ'],
    ['c_control', '状态机、捕获门、故障处理、输出级例化', 'u、state、fault'],
    ['c_balance_core', '四状态反馈律与定点乘加流水', 'u（Q16 V）'],
    ['c_swing', '能量泵、余弦查表、软限位与臂阻尼', 'u（起摆态）'],
    ['c_output / c_pwm', '限幅、压摆、死区补偿、20 kHz PWM', 'duty（‰）'],
    ['c_trace_*', '896 bit × 2048 条记录与串口上传', 'UART 115200'],
], '表 2　模块职责与关键接口', widths=[3.6, 8.4, 4.0])

h('2.2　硬件系统介绍', 2)
h('2.2.1　硬件整体', 3)
para('核心板以 GW2A-LV55PG484C8/I7 为主控，外接 50 MHz 晶振，经排线与实验箱的传感器接口、'
     '驱动接口相连；12 V 单电源供电，板上稳压 3.3 V 供 FPGA 与传感器。电机与逻辑共地，'
     '但电机回流线与电位器信号线分开走，PWM 与电机线成对绞合后远离 ADC 信号，'
     '电位器地线单独回到 ADC 地。')
photo(13.0, 5.2, '【照片 P1】硬件整体',
      '拍：核心板 + 驱动板 + 电源 + 接线全貌，能看清三块板之间的排线走向')

h('2.2.2　机械设计', 3)
para('旋臂与摆杆均为 152 mm × 36 mm 铝制杆件，质量各约 90 g；摆杆通过轴承铰接在旋臂末端，'
     '绕水平轴自由转动；旋臂由 12 V 直流减速电机经 20:1 齿轮箱驱动；摆杆角度由同轴电位器测量，'
     '旋臂角度由电机侧增量编码器测量，分辨率分别为 0.080°/count 与 0.335°/count。'
     '机械上只做了调平、螺钉复紧与线束整理，没有改动结构件。')
photo_pair('【照片 P2】整机结构', '拍：斜 45° 能看到电机、旋臂、摆杆、电位器支架的相对位置',
           '【照片 P3】转轴与铰接', '拍：电机轴—联轴器—旋臂根部、摆杆铰点与电位器同轴处（微距）', 5.2)

h('2.2.3　电路各模块', 3)
para('电路分四块：ADC 采样（10 位并行，5 MHz 采样时钟，128 点硬件均值）、编码器接口'
     '（A/B 相四倍频计数）、电机驱动（TB6612 双极性，20 kHz PWM，指令限幅 ±6 V）、'
     '人机与通信（SW1/SW3 按键、UART 115200）。各模块的关键输入输出信号线在原理图上已标注。')
photo_pair('【照片 P4】原理图', '拍：屏幕上 ADC、编码器、驱动、按键四部分的 SCH 截图，标注信号名',
           '【照片 P5】PCB 与实物板', '拍：核心板/驱动板正反面，能看清丝印与接口', 5.2)

h('2.3　软件系统介绍', 2)
h('2.3.1　软件整体', 3)
para('软件分三层：采样层（c_adc、c_encoder）、控制层（c_sensor、c_control、c_balance_core、'
     'c_swing）、输出与记录层（c_output、c_pwm、c_trace_*）。图 2 是平衡态的完整信号流：'
     '两路跟踪器把角度变成角度加角速度的四状态向量，LQR 按 Q8 增益求和得到电压指令，'
     '经陷波、限幅、压摆后映射为占空比。上位机为 MATLAB 脚本，只做状态帧解析、轨迹回传与 CSV 落盘。')
figure('fig2_control.png', '图 2　平衡控制信号流', 14.8)

h('2.3.2　软件各模块', 3)
para('c_sensor：输入 raw12 与编码器计数，输出 θ、a 及四路速度估计。内部先做角度换算'
     '（θ=(up12−raw12)×0.0801°），再进两路常速度跟踪器：p̂←p̂+Ts·v̂+L₁·e，v̂←v̂+L₂·e，'
     'Ts=1 ms，旋臂通道 L₁=0.222、L₂=9.76，摆杆通道 L₁=0.395、L₂=49.4。')
para('c_balance_core：输入四状态，输出 u=538Δa+650v_a+4690θ+450ω_θ（V），'
     '定点乘加分四级流水，约 120 个时钟完成一次运算；|θ|>12° 时 KQ₁ 由 650 降到 315，'
     '回到 10° 以内恢复。')
para('c_control：状态机（图 3）与保护。起摆态由 c_swing 输出能量泵指令，捕获门为'
     '|θ|<20°、|dθ/dt|<3.0 rad/s、连续 3 拍；平衡态监督运行时长、传感器新鲜度与臂行程，'
     '异常一律断输出并记录故障码。')
figure('fig4_fsm.png', '图 3　控制状态机与故障恢复路径', 13.0)
para('c_output：输入电压指令，先做限幅（±6 V）与压摆（平衡 60‰/ms、起摆 100‰/ms），'
     '再按 500‰ 对应 6 V 映射为占空比；陷波器一级双二阶，系数以 Q28 存放，'
     '中心 12.5 Hz、带宽 12 Hz、深度 0.6，幅频特性见图 4。')
figure('fig3_notch.png', '图 4　陷波器幅频特性（由 RTL 定点系数计算）', 12.5)

brk()
# ================================================================ 第三部分
h('第三部分　完成情况及性能参数', 1)

h('3.1　整体介绍', 2)
para('系统在新套件上完成全部功能验证：起摆、平衡、抗扰、点位、整圈旋转、跌倒自恢复均可用，'
     '定版三次 30 s 长跑全部跑满（故障码 7），触轨 0%、滑脱 0 次。')
photo_pair('【照片 P6】整机正面', '拍：正对设备，摆杆直立，背景干净（注意不要拍到校名）',
           '【照片 P7】整机斜 45°', '拍：斜 45° 全局照，能同时看到机械、板卡、接线', 5.6)

h('3.2　工程成果', 2)
h('3.2.1　机械成果', 3)
photo(14.0, 4.2, '【照片 P8】机械成果', '拍：减速箱、旋臂、摆杆、电位器固定方式的近景')
h('3.2.2　电路成果', 3)
photo(14.0, 4.2, '【照片 P9】电路成果', '拍：核心板与驱动板装配后的实物，可见接线端子与排线')
h('3.2.3　软件成果', 3)
photo(14.0, 4.6, '【照片 P10】上位机界面', '拍：串口采集窗口，显示 θ、a、占空比、故障码与波形')

h('3.3　特性成果', 2)
para('图 5 是时域对比：旧交付版旋臂以约 0.5 Hz 做大幅慢摆，N21 的旋臂贴在零位，'
     '曲线上的平台段是旋臂静止、电机蓄力越过静摩擦的时段。图 6 是占空比指令幅值谱，'
     '3–18 Hz 整段下降。图 7 是整圈旋转，30 s 累计 385°，恒速段 21.0°/s。')
table(['功能', '测试条件', '结果'], [
    ['自动起摆', '摆杆垂下垂，SW3 按住 0.8 s', '起摆后接管平衡，现场多次复现'],
    ['平衡稳定', '30 s 长跑', '臂峰峰 15.7/15.7/17.7°，θRMS 1.60/1.56/2.15°'],
    ['抗扰', '手推摆杆 5–8°', '自行回正；|θ|>12° 降增益（现场验证）'],
    ['点位', 'SW1 循环 0/+30/+60°', '参考 10°/s 平滑移动（现场验证）'],
    ['整圈旋转', '参考 21.0°/s', '30 s 累计 385°，|θ|≤9.5°、RMS 2.2°'],
    ['跌倒重起', '手推倒，摆杆过 40°', '切断→垂下 1.5 s→自动重起（现场验证）'],
], '表 3　功能测试记录', widths=[3.2, 5.6, 7.2])
figure('fig6_timedomain.png', '图 5　稳态时域对比（各一次 30 s 长跑）', 14.4)
figure('fig7_spectrum.png', '图 6　占空比指令幅值谱（10–30 s）', 14.4)
figure('fig8_rotation.png', '图 7　整圈旋转时序', 14.4)


brk()
# ================================================================ 第四部分
h('第四部分　总结', 1)

h('4.1　可扩展之处', 2)
P41 = ('（1）机械侧：齿轮箱与输出轴重新润滑，把慢速试验测得的起动占空比从 170–223‰ 压到 100‰ '
       '以下；换低齿隙减速箱或用同步带传动；用绝对值编码器替代电位器，从根上消除零点随臂角'
       '±3° 的正弦漂移。这三条中的任何一条，效果都超过控制侧的所有努力。'
       '（2）控制侧：位置项加低通（慢但不积累），以及带输入整形的参考轨迹，抑制参考切换激发的慢摆；'
       '两者都需要额外的乘法器与时序余量，在 DSP 已占 88% 的情况下要先做资源腾挪。'
       '（3）功能侧：把点位扩展为任意角度与连续轨迹，把整圈旋转扩展为多圈与变速，'
       '都只需改参考生成，控制律不变。')
para(P41)
print('4.1字数', len(P41))

h('4.2　心得体会', 2)
X = [
 '这个题我们做了将近一个月。最后留在手里的东西比预想的少，也比预想的实在。',
 '最开始的两周基本走错了方向。摆不起来、立不住，第一反应是增益不对，于是一版一版地烧、一次一次地调 KQ。'
 '直到有一天把电机座的四颗螺钉拧紧，同样的固件臂摆从六十度掉到二十度，才明白前面调的大半是机械的账。'
 '这件事之后我们把顺序固定成"先机械、后参数"，桌面调平、螺钉复紧、零点标定各做一遍，再谈增益。'
 '现在回头看，那两周并不算白费：正是因为把增益的四个方向都试遍了（加倍、取负、继续增大、分状态），'
 '才知道这条路的天花板在哪。',
 '第二件教训是别用单跑下结论。同一个固件，两次跑出十八度和三十六度的臂摆，我们拿第一次的数据'
 '兴奋了半小时，第二次就被推翻。后来定下规矩：每版至少两跑，比较看中位数和离散范围；'
 '一条曲线要三个点以上才敢说是趋势。这条规矩救了我们至少三次。',
 '第三件是"聪明的方案"往往死得最快。位置积分看起来能消稳态误差，实测积分钉在钳位上把臂推走；'
 '死区逆补偿看起来能治黏滑，实测把慢摆放大一倍；分状态增益看起来能各取所长，实测切换的阶跃本身'
 '灌进十到二十五赫兹的能量。三次失败有一个共同点：我们先把机理想清楚了，再去看数据，'
 '而数据说的是另一回事。后来改成先统计、再设计——比如起动阈值那次，统计了一千九百多次黏滑事件，'
 '才发现占空比中位数已经到二百七十四千分比，满量程只有五百，这个数一出来，所有"再调调参数"的想法'
 '就都不成立了。',
 '还有一次是数据的口径。我们拿六十二点五赫兹抽稀的轨迹去统计角度占比，算出百分之四点三，'
 '照着这个数定了门限；上板才发现那个门限一半的时间都满足。同一份数据换个采样率就是另一个结论，'
 '这件事让我们后来每个阈值都要在同口径的信号上重算一遍。',
 '最后一天换到了新套件。摩擦更大，老固件在新套件上起不来。改了三处纯起摆参数（耐心、软限位、'
 '臂阻尼）之后能起摆了，但真正把臂摆压下去的还是调平和复紧。这算是把这个月学到的道理又验证了一遍。',
 '如果重来一次，我们会先花一天把机械做到最好，再用两天把测量与统计的工具搭好，然后才动控制参数。'
 '控制律能做的，是把机械的边界翻译成一组数字；边界本身在机械上。',
]
for t in X:
    para(t)
print('4.2字数', sum(len(t) for t in X))

brk()
# ================================================================ 第五部分
h('第五部分　参考文献', 1)
refs = [
 '[1] Gowin Semiconductor. GW2A Series FPGA Products Datasheet, DS102-2.7.6E. 高云半导体文档中心.',
 '[2] Gowin Semiconductor. GW2A-55 & GW2A-55C Pinout User Guide, UG113-1.5.6E.',
 '[3] Gowin Semiconductor. Gowin Design Timing Constraints User Guide, SUG940-2.0.1E.',
 '[4] Kalman R E. A New Approach to Linear Filtering and Prediction Problems. Journal of Basic Engineering, 1960, 82(1): 35–45.',
 '[5] Anderson B D O, Moore J B. Optimal Control: Linear Quadratic Methods. Prentice Hall, 1990.',
 '[6] Åström K J, Murray R M. Feedback Systems: An Introduction for Scientists and Engineers. Princeton University Press, 2008.',
 '[7] Ogata K. Modern Control Engineering, 5th ed. Prentice Hall, 2010.',
 '[8] Furuta K, Yamakita M, Kobayashi S. Swing-up Control of Inverted Pendulum Using Pseudo-State Feedback. Proc. IMechE Part I, 1992, 206(4): 263–269.',
 '[9] Åström K J, Furuta K. Swinging up a Pendulum by Energy Control. Automatica, 2000, 36(2): 287–295.',
 '[10] Ljung L. System Identification: Theory for the User, 2nd ed. Prentice Hall, 1999.',
]
for r in refs:
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.line_spacing = 1.3
    pf.left_indent = Pt(24)
    pf.first_line_indent = Pt(-24)
    pf.space_after = Pt(2)
    pf.alignment = WD_ALIGN_PARAGRAPH.LEFT
    set_run(p.add_run(r), size=9)

doc.save(OUT)
print('saved', OUT)
