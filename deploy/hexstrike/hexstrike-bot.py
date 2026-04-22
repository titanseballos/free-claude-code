#!/usr/bin/env python3
import re
import json
import requests
from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes

TOKEN = "8797545165:AAGWX8hM9ePMk63I60cz8WVS3QEBbcBAQhc"
AUTHORIZED_USER = 7035504055
HEXSTRIKE = "http://localhost:8888"
import os
GROQ_KEY = os.environ.get("GROQ_API_KEY", "")
MODEL = "llama-3.3-70b-versatile"
SYSTEM = (
    "Sos un experto en ciberseguridad ofensiva y defensiva. "
    "Respondés en español de forma técnica y concisa. "
    "Solo ejecutás tareas sobre objetivos autorizados. "
    "Cuando des resultados de herramientas, resumís los hallazgos más importantes."
)

TOOLS = {
    "subfinder": lambda t: f"subfinder -d {t} -silent",
    "amass": lambda t: f"amass enum -d {t}",
    "nmap": lambda t: f"nmap -sV -p 1-1000 {t}",
    "nikto": lambda t: f"nikto -h {t}",
    "sqlmap": lambda t: f"sqlmap -u {t} --batch --level 1",
    "gobuster": lambda t: f"gobuster dir -u {t} -w /usr/share/wordlists/dirb/common.txt",
    "whatweb": lambda t: f"whatweb {t}",
    "wafw00f": lambda t: f"wafw00f {t}",
    "httpx": lambda t: f"httpx -u {t}",
    "nuclei": lambda t: f"nuclei -u {t} -silent",
    "ffuf": lambda t: f"ffuf -u {t}/FUZZ -w /usr/share/wordlists/dirb/common.txt -mc 200,301,302",
    "dig": lambda t: f"dig {t} ANY",
    "whois": lambda t: f"whois {t}",
    "theHarvester": lambda t: f"theHarvester -d {t} -b all",
}

TOOL_LIST = "\n".join(f"- {k}" for k in TOOLS)

DECISION_PROMPT = """Analiza este pedido de seguridad: "{msg}"

Herramientas disponibles:
{tools}

Responde SOLO con JSON válido (sin texto extra):
{{"tool": "nombre_herramienta", "target": "objetivo_exacto", "reason": "motivo"}}

Si el pedido no es una tarea de seguridad técnica, responde:
{{"tool": "none", "target": "", "reason": "motivo"}}"""

ANALYSIS_PROMPT = """Ejecuté el siguiente comando de seguridad:
Comando: {cmd}

Resultado:
{result}

Analiza estos resultados y dame un resumen técnico en español. Identifica:
- Subdominios encontrados
- Puertos y servicios abiertos
- Vulnerabilidades detectadas
- Tecnologías identificadas
- Recomendaciones de seguridad
Solo incluye lo que sea relevante para los resultados obtenidos."""


def ai(prompt: str) -> str:
    try:
        r = requests.post(
            "https://api.groq.com/openai/v1/chat/completions",
            headers={"Authorization": f"Bearer {GROQ_KEY}"},
            json={
                "model": MODEL,
                "messages": [
                    {"role": "system", "content": SYSTEM},
                    {"role": "user", "content": prompt},
                ],
            },
            timeout=60,
        )
        return r.json()["choices"][0]["message"]["content"]
    except Exception as e:
        return f"Error AI: {e}"


def hs(command: str) -> str:
    try:
        r = requests.post(
            f"{HEXSTRIKE}/api/command",
            json={"command": command},
            timeout=120,
        )
        data = r.json()
        return data.get("stdout") or data.get("output") or data.get("result") or str(data)
    except Exception as e:
        return f"Error HexStrike: {e}"


def auth(update: Update) -> bool:
    return update.effective_user.id == AUTHORIZED_USER


async def cmd_start(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not auth(update):
        return
    await update.message.reply_text(
        "HexStrike AI activo.\n\n"
        "Comandos:\n"
        "/status - Estado del servidor\n"
        "/tools - Herramientas disponibles\n"
        "/scan <objetivo> - Nmap\n"
        "/sub <dominio> - Subfinder\n"
        "/web <url> - Nikto\n"
        "/sql <url> - SQLmap\n"
        "/tech <url> - WhatWeb\n"
        "/ask <pregunta> - Consulta AI\n\n"
        "O escribí directamente lo que querés hacer."
    )


async def cmd_status(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not auth(update):
        return
    try:
        r = requests.get(f"{HEXSTRIKE}/health", timeout=10)
        data = r.json()
        tools_active = data.get("tools_available", "?")
        status = data.get("status", "unknown")
        await update.message.reply_text(f"HexStrike: {status}\nHerramientas activas: {tools_active}")
    except Exception as e:
        await update.message.reply_text(f"No se puede conectar al servidor: {e}")


async def cmd_tools(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not auth(update):
        return
    await update.message.reply_text(f"Herramientas configuradas:\n{TOOL_LIST}")


async def cmd_scan(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not auth(update):
        return
    args = ctx.args
    if not args:
        await update.message.reply_text("Uso: /scan <objetivo>")
        return
    target = args[0]
    await update.message.reply_text(f"Ejecutando nmap en {target}...")
    result = hs(TOOLS["nmap"](target))
    await update.message.reply_text(f"```\n{result[:3500]}\n```", parse_mode="Markdown")


async def cmd_sub(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not auth(update):
        return
    args = ctx.args
    if not args:
        await update.message.reply_text("Uso: /sub <dominio>")
        return
    target = args[0]
    await update.message.reply_text(f"Buscando subdominios de {target}...")
    result = hs(TOOLS["subfinder"](target))
    await update.message.reply_text(f"```\n{result[:3500]}\n```", parse_mode="Markdown")


async def cmd_web(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not auth(update):
        return
    args = ctx.args
    if not args:
        await update.message.reply_text("Uso: /web <url>")
        return
    target = args[0]
    await update.message.reply_text(f"Ejecutando nikto en {target}...")
    result = hs(TOOLS["nikto"](target))
    await update.message.reply_text(f"```\n{result[:3500]}\n```", parse_mode="Markdown")


async def cmd_sql(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not auth(update):
        return
    args = ctx.args
    if not args:
        await update.message.reply_text("Uso: /sql <url>")
        return
    target = args[0]
    await update.message.reply_text(f"Ejecutando sqlmap en {target}...")
    result = hs(TOOLS["sqlmap"](target))
    await update.message.reply_text(f"```\n{result[:3500]}\n```", parse_mode="Markdown")


async def cmd_tech(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not auth(update):
        return
    args = ctx.args
    if not args:
        await update.message.reply_text("Uso: /tech <url>")
        return
    target = args[0]
    await update.message.reply_text(f"Detectando tecnologías en {target}...")
    result = hs(TOOLS["whatweb"](target))
    await update.message.reply_text(f"```\n{result[:3500]}\n```", parse_mode="Markdown")


async def cmd_ask(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not auth(update):
        return
    if not ctx.args:
        await update.message.reply_text("Uso: /ask <pregunta>")
        return
    question = " ".join(ctx.args)
    answer = ai(question)
    await update.message.reply_text(answer[:4000])


async def agente(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not auth(update):
        return
    msg = update.message.text
    await update.message.reply_text("Analizando pedido...")

    decision_raw = ai(DECISION_PROMPT.format(msg=msg, tools=TOOL_LIST))

    try:
        match = re.search(r"\{.*\}", decision_raw, re.DOTALL)
        if not match:
            raise ValueError("no JSON")
        parsed = json.loads(match.group())
        tool = parsed.get("tool", "none")
        target = parsed.get("target", "").strip()

        if tool == "none" or not target:
            answer = ai(msg)
            await update.message.reply_text(answer[:4000])
            return

        cmd = TOOLS.get(tool, lambda t: f"{tool} {t}")(target)
        await update.message.reply_text(f"Ejecutando `{tool}` en `{target}`...", parse_mode="Markdown")

        result = hs(cmd)
        analysis = ai(ANALYSIS_PROMPT.format(cmd=cmd, result=result[:3000]))

        output = result[:1500]
        await update.message.reply_text(f"```\n{output}\n```", parse_mode="Markdown")
        await update.message.reply_text(f"**Análisis:**\n{analysis[:2500]}", parse_mode="Markdown")

    except Exception:
        answer = ai(msg)
        await update.message.reply_text(answer[:4000])


def main() -> None:
    app = Application.builder().token(TOKEN).build()
    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(CommandHandler("status", cmd_status))
    app.add_handler(CommandHandler("tools", cmd_tools))
    app.add_handler(CommandHandler("scan", cmd_scan))
    app.add_handler(CommandHandler("sub", cmd_sub))
    app.add_handler(CommandHandler("web", cmd_web))
    app.add_handler(CommandHandler("sql", cmd_sql))
    app.add_handler(CommandHandler("tech", cmd_tech))
    app.add_handler(CommandHandler("ask", cmd_ask))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, agente))
    app.run_polling()


if __name__ == "__main__":
    main()
