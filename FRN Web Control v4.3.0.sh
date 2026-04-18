#!/bin/bash
# FRN Web Control v4.3.0 - Расширенная версия со всеми серверами FRN
# Поддержка Orange Pi и Raspberry Pi
# Автор: RW6HHL 2026

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

CHECK_MARK="✅"
CROSS_MARK="❌"
WARN_MARK="⚠️"
INFO_MARK="📌"
ROCKET_MARK="🚀"
WEB_MARK="🌐"
GPIO_MARK="🔌"

clear
echo ""
echo -e "${GREEN} FRN Web Control v4.3.0 - РАСШИРЕННАЯ ВЕРСИЯ${NC}"
echo -e "${GREEN} Поддержка всех серверов FRN из списка${NC}"
echo ""

# Проверка прав
if [ "$EUID" -eq 0 ]; then 
    echo -e "${RED}${CROSS_MARK} НЕ ЗАПУСКАЙТЕ ОТ ROOT! Используйте пользователя pi${NC}"
    exit 1
fi

# Определение платформы
PLATFORM="unknown"
if [ -f /etc/orangepi-release ] || grep -q "Orange Pi" /proc/cpuinfo 2>/dev/null; then
    PLATFORM="orangepi"
    echo -e "${INFO_MARK} Обнаружена платформа: Orange Pi${NC}"
elif grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
    PLATFORM="raspberry"
    echo -e "${INFO_MARK} Обнаружена платформа: Raspberry Pi${NC}"
else
    echo -e "${YELLOW}${WARN_MARK} Неизвестная платформа, пробуем универсальный режим${NC}"
    PLATFORM="generic"
fi

# Создание директории для логов
INSTALL_LOG_DIR="/home/pi/frn-web-install-logs"
mkdir -p "$INSTALL_LOG_DIR"
INSTALL_LOG="$INSTALL_LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
touch "$INSTALL_LOG"

log() {
    echo -e "$1" | tee -a "$INSTALL_LOG"
}

check_error() {
    if [ $? -ne 0 ]; then
        echo ""
        echo -e "${RED}${CROSS_MARK} ОШИБКА: $1${NC}"
        echo -e "${YELLOW}${WARN_MARK} Лог: $INSTALL_LOG${NC}"
        exit 1
    fi
}

# ============================================================================
# ШАГ 1: УДАЛЕНИЕ СТАРОЙ ВЕРСИИ
# ============================================================================

echo ""
echo -e "${YELLOW}--- ШАГ 1: Удаление старой версии ---${NC}"
echo ""

echo -n "[1/10] Остановка сервиса... "
sudo systemctl stop frn-web.service 2>/dev/null
sudo systemctl disable frn-web.service 2>/dev/null
sudo systemctl kill frn-web.service 2>/dev/null
sudo rm /etc/systemd/system/frn-web.service 2>/dev/null
sudo systemctl daemon-reload
echo -e "${GREEN}${CHECK_MARK}${NC}"

echo -n "[2/10] Создание резервной копии... "
BACKUP_DIR="/home/pi/frn-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
for dir in AFRNClient FRNClient; do
    if [ -f "/home/pi/$dir/frnconsole.cfg.unix" ]; then
        cp "/home/pi/$dir/frnconsole.cfg.unix" "$BACKUP_DIR/frnconsole.cfg.unix.$dir" 2>/dev/null
    fi
done
echo -e "${GREEN}${CHECK_MARK}${NC}"

echo -n "[3/10] Удаление файлов проекта... "
rm -rf /home/pi/frn-web 2>/dev/null
echo -e "${GREEN}${CHECK_MARK}${NC}"

echo -n "[4/10] Удаление скриптов... "
sudo rm /usr/local/bin/switch_frn_room.sh 2>/dev/null
sudo rm /usr/local/bin/frn-web-control 2>/dev/null
sudo rm /usr/local/bin/rx_gpio_monitor 2>/dev/null
echo -e "${GREEN}${CHECK_MARK}${NC}"

echo -n "[5/10] Очистка временных файлов... "
sudo rm -f /tmp/rx_gpio_state 2>/dev/null
echo -e "${GREEN}${CHECK_MARK}${NC}"

echo -n "[6/10] Удаление правил sudo... "
sudo rm /etc/sudoers.d/frn 2>/dev/null
echo -e "${GREEN}${CHECK_MARK}${NC}"

echo -n "[7/10] Остановка FRN клиента... "
sudo pkill -f "AFRNClient|FRNClient" 2>/dev/null
sleep 1
echo -e "${GREEN}${CHECK_MARK}${NC}"

echo -n "[8/10] Остановка монитора GPIO... "
sudo pkill -f rx_gpio_monitor 2>/dev/null
echo -e "${GREEN}${CHECK_MARK}${NC}"

echo -n "[9/10] Очистка кэша npm... "
npm cache clean --force 2>/dev/null
echo -e "${GREEN}${CHECK_MARK}${NC}"

echo -n "[10/10] Проверка удаления... "
if [ -d /home/pi/frn-web ]; then
    echo -e "${RED}${CROSS_MARK}${NC}"
    exit 1
else
    echo -e "${GREEN}${CHECK_MARK}${NC}"
fi

echo ""
echo -e "${GREEN}${CHECK_MARK} Удаление завершено${NC}"
echo ""

# ============================================================================
# ШАГ 2: ВЫБОР ДИРЕКТОРИИ FRN КЛИЕНТА
# ============================================================================

echo -e "${YELLOW}--- ШАГ 2: Выбор директории FRN клиента ---${NC}"
echo ""

POSSIBLE_DIRS=()
for dir in /home/pi/AFRNClient /home/pi/FRNClient /home/pi/frn; do
    if [ -d "$dir" ]; then
        POSSIBLE_DIRS+=("$dir")
    fi
done

FRN_DIR=""
if [ ${#POSSIBLE_DIRS[@]} -gt 0 ]; then
    echo -e "${INFO_MARK} Найдены директории:"
    echo ""
    for i in "${!POSSIBLE_DIRS[@]}"; do
        DIR="${POSSIBLE_DIRS[$i]}"
        if [ -f "$DIR/frnconsole.cfg.unix" ]; then
            echo "  [$((i+1))] $DIR (конфиг найден)"
        else
            echo "  [$((i+1))] $DIR (конфиг НЕ найден)"
        fi
    done
    echo "  [$(( ${#POSSIBLE_DIRS[@]} + 1 ))] Указать другой путь"
    echo ""
    
    while true; do
        printf "${YELLOW}Выберите номер (1-$(( ${#POSSIBLE_DIRS[@]} + 1 ))): ${NC}"
        read dir_choice
        
        if [[ "$dir_choice" =~ ^[0-9]+$ ]]; then
            if [ "$dir_choice" -ge 1 ] && [ "$dir_choice" -le "${#POSSIBLE_DIRS[@]}" ]; then
                FRN_DIR="${POSSIBLE_DIRS[$((dir_choice-1))]}"
                echo -e "${GREEN}${CHECK_MARK} Выбрано: $FRN_DIR${NC}"
                break
            elif [ "$dir_choice" -eq "$(( ${#POSSIBLE_DIRS[@]} + 1 ))" ]; then
                printf "${YELLOW}Введите путь: ${NC}"
                read custom_dir
                if [[ "$custom_dir" != /* ]]; then
                    custom_dir="/home/pi/$custom_dir"
                fi
                FRN_DIR="$custom_dir"
                echo -e "${GREEN}${CHECK_MARK} Указано: $FRN_DIR${NC}"
                break
            else
                echo -e "${RED}Неверный номер${NC}"
            fi
        else
            echo -e "${RED}Введите число${NC}"
        fi
    done
else
    printf "${YELLOW}Введите путь к FRN клиенту: ${NC}"
    read custom_dir
    if [[ "$custom_dir" != /* ]]; then
        custom_dir="/home/pi/$custom_dir"
    fi
    FRN_DIR="$custom_dir"
fi

# Проверка исполняемого файла
FRN_BINARY=""
if [ -f "$FRN_DIR/AFRNClient" ] && [ -x "$FRN_DIR/AFRNClient" ]; then
    FRN_BINARY="$FRN_DIR/AFRNClient"
    FRN_BIN_NAME="AFRNClient"
elif [ -f "$FRN_DIR/FRNClient" ] && [ -x "$FRN_DIR/FRNClient" ]; then
    FRN_BINARY="$FRN_DIR/FRNClient"
    FRN_BIN_NAME="FRNClient"
elif [ -f "$FRN_DIR/frnclient" ] && [ -x "$FRN_DIR/frnclient" ]; then
    FRN_BINARY="$FRN_DIR/frnclient"
    FRN_BIN_NAME="frnclient"
else
    echo -e "${RED}${CROSS_MARK} Исполняемый файл не найден${NC}"
    exit 1
fi

# Проверка конфига
FRN_CONFIG="$FRN_DIR/frnconsole.cfg.unix"
if [ ! -f "$FRN_CONFIG" ]; then
    echo -e "${RED}${CROSS_MARK} Конфиг не найден: $FRN_CONFIG${NC}"
    exit 1
fi

# Чтение параметров
EMAIL=$(grep "^EMailAddress=" "$FRN_CONFIG" | cut -d'=' -f2 | tr -d '\r' | xargs)
CALLSIGN=$(grep "^Callsign=" "$FRN_CONFIG" | cut -d'=' -f2 | tr -d '\r' | xargs)
CITY=$(grep "^City=" "$FRN_CONFIG" | cut -d'=' -f2 | tr -d '\r' | xargs)
FREQUENCY=$(grep "^BandChannel=" "$FRN_CONFIG" | cut -d'=' -f2 | tr -d '\r' | xargs)

[ -z "$EMAIL" ] && EMAIL="не указан"
[ -z "$CALLSIGN" ] && CALLSIGN="не указан"
[ -z "$CITY" ] && CITY="не указан"
[ -z "$FREQUENCY" ] && FREQUENCY="не указана"

echo ""
echo -e "${GREEN}${CHECK_MARK} Найден линк:${NC}"
echo "  Email: $EMAIL"
echo "  Позывной: $CALLSIGN"
echo "  Город: $CITY"
echo "  Частота: $FREQUENCY"
echo ""

# ============================================================================
# ШАГ 3: УСТАНОВКА
# ============================================================================

echo -e "${YELLOW}--- ШАГ 3: Установка ---${NC}"
echo ""

echo -n "[1/15] Проверка компилятора... "
if ! command -v gcc &> /dev/null; then
    sudo apt update >> "$INSTALL_LOG" 2>&1
    sudo apt install -y build-essential >> "$INSTALL_LOG" 2>&1
fi
echo -e "${GREEN}${CHECK_MARK}${NC}"

echo -n "[2/15] Установка git... "
if ! command -v git &> /dev/null; then
    sudo apt install -y git >> "$INSTALL_LOG" 2>&1
fi
echo -e "${GREEN}${CHECK_MARK}${NC}"

echo -n "[3/15] Установка библиотек GPIO... "
if [ "$PLATFORM" = "orangepi" ]; then
    if ! command -v gpio &> /dev/null; then
        cd /tmp
        git clone https://github.com/orangepi-xunlong/wiringOP.git >> "$INSTALL_LOG" 2>&1
        cd wiringOP
        sudo ./build clean >> "$INSTALL_LOG" 2>&1
        sudo ./build >> "$INSTALL_LOG" 2>&1
        cd ..
        rm -rf wiringOP
        echo -e "${GREEN}${CHECK_MARK} (WiringOP)${NC}"
    else
        echo -e "${GREEN}${CHECK_MARK}${NC}"
    fi
elif [ "$PLATFORM" = "raspberry" ]; then
    if ! command -v gpio &> /dev/null; then
        cd /tmp
        wget -q https://project-downloads.drogon.net/wiringpi-latest.deb >> "$INSTALL_LOG" 2>&1
        sudo dpkg -i wiringpi-latest.deb >> "$INSTALL_LOG" 2>&1
        rm wiringpi-latest.deb 2>/dev/null
        echo -e "${GREEN}${CHECK_MARK} (WiringPi)${NC}"
    else
        echo -e "${GREEN}${CHECK_MARK}${NC}"
    fi
else
    echo -e "${GREEN}${CHECK_MARK} (пропущено)${NC}"
fi

echo -n "[4/15] Проверка Node.js... "
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - >> "$INSTALL_LOG" 2>&1
    sudo apt install -y nodejs >> "$INSTALL_LOG" 2>&1
fi
echo -e "${GREEN}${CHECK_MARK}${NC}"

echo -n "[5/15] Создание структуры... "
cd /home/pi
rm -rf /home/pi/frn-web 2>/dev/null
mkdir -p frn-web/{public,logs,backup,tmp,data}
sudo chown -R pi:pi /home/pi/frn-web
echo -e "${GREEN}${CHECK_MARK}${NC}"

echo -n "[6/15] Создание конфигов... "
cat > /home/pi/frn-web/data/gpio_config.json << 'EOF'
{"rx_gpio2_duration":0.5,"gpio_pin":2,"last_update":"2026-03-20T00:00:00Z"}
EOF

cat > /home/pi/frn-web/data/frn_path.json << EOF
{"frn_dir":"$FRN_DIR","frn_binary":"$FRN_BINARY","frn_bin_name":"$FRN_BIN_NAME","frn_config":"$FRN_CONFIG"}
EOF
sudo chown pi:pi /home/pi/frn-web/data/*
echo -e "${GREEN}${CHECK_MARK}${NC}"

echo -n "[7/15] Инициализация npm... "
cat > /home/pi/frn-web/package.json << 'EOF'
{"name":"frn-web-control","version":"4.3.0","main":"server.js","dependencies":{"express":"^4.18.2","ws":"^8.14.2"}}
EOF
echo -e "${GREEN}${CHECK_MARK}${NC}"

echo -n "[8/15] Установка зависимостей... "
cd /home/pi/frn-web
npm install express ws >> "$INSTALL_LOG" 2>&1
echo -e "${GREEN}${CHECK_MARK}${NC}"

echo -n "[9/15] Настройка прав... "
sudo mkdir -p /var/run/frn
sudo chown pi:pi /var/run/frn
if ! getent group gpio > /dev/null; then
    sudo groupadd gpio
fi
sudo usermod -a -G gpio pi
echo -e "${GREEN}${CHECK_MARK}${NC}"

echo -n "[10/15] Настройка sudo... "
sudo tee /etc/sudoers.d/frn > /dev/null << EOF
pi ALL=(ALL) NOPASSWD: $FRN_BINARY
pi ALL=(ALL) NOPASSWD: /usr/bin/pkill
pi ALL=(ALL) NOPASSWD: /bin/pkill
pi ALL=(ALL) NOPASSWD: /usr/bin/gpio
EOF
sudo chmod 440 /etc/sudoers.d/frn
echo -e "${GREEN}${CHECK_MARK}${NC}"

echo -n "[11/15] Компиляция GPIO монитора... "
cat > /tmp/rx_gpio_monitor.c << 'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/time.h>
#include <signal.h>
#include <errno.h>

#define GPIO_PIN 2
#define GPIO_PATH "/sys/class/gpio"
#define STATE_FILE "/tmp/rx_gpio_state"
#define CONFIG_FILE "/home/pi/frn-web/data/gpio_config.json"

volatile int running = 1;
int last_state = 1;
struct timeval last_change;
double min_duration = 0.5;
int gpio_fd = -1;

double read_min_duration() {
    FILE *fp = fopen(CONFIG_FILE, "r");
    if (!fp) return min_duration;
    char buffer[256];
    size_t n = fread(buffer, 1, sizeof(buffer)-1, fp);
    fclose(fp);
    if (n > 0) {
        buffer[n] = '\0';
        char *p = strstr(buffer, "\"rx_gpio2_duration\"");
        if (p) {
            p = strchr(p, ':');
            if (p) {
                p++;
                double val = strtod(p, NULL);
                if (val >= 0 && val <= 2.0) return val;
            }
        }
    }
    return min_duration;
}

void handle_signal(int sig) { running = 0; }

void write_state(int pin_state, double duration) {
    FILE *fp = fopen(STATE_FILE, "w");
    if (fp) {
        fprintf(fp, "%d %.3f\n", pin_state, duration);
        fflush(fp);
        fclose(fp);
    }
}

int init_gpio() {
    FILE *fp = fopen(GPIO_PATH "/export", "w");
    if (fp) {
        fprintf(fp, "%d", GPIO_PIN);
        fclose(fp);
        usleep(100000);
    }
    
    char dir_path[256];
    snprintf(dir_path, sizeof(dir_path), GPIO_PATH "/gpio%d/direction", GPIO_PIN);
    fp = fopen(dir_path, "w");
    if (fp) {
        fprintf(fp, "in");
        fclose(fp);
    } else {
        return -1;
    }
    
    char val_path[256];
    snprintf(val_path, sizeof(val_path), GPIO_PATH "/gpio%d/value", GPIO_PIN);
    gpio_fd = open(val_path, O_RDONLY);
    if (gpio_fd < 0) return -1;
    
    return 0;
}

int read_gpio() {
    if (gpio_fd < 0) return 1;
    lseek(gpio_fd, 0, SEEK_SET);
    char buf[2];
    if (read(gpio_fd, buf, 1) != 1) return 1;
    return (buf[0] == '0') ? 0 : 1;
}

void cleanup_gpio() {
    if (gpio_fd >= 0) close(gpio_fd);
    FILE *fp = fopen(GPIO_PATH "/unexport", "w");
    if (fp) {
        fprintf(fp, "%d", GPIO_PIN);
        fclose(fp);
    }
}

int main() {
    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);
    
    if (init_gpio() < 0) {
        fprintf(stderr, "Warning: Cannot initialize GPIO, using emulation mode\n");
        last_state = 1;
        gettimeofday(&last_change, NULL);
        while (running) {
            min_duration = read_min_duration();
            usleep(50000);
            write_state(1, 0);
        }
        return 0;
    }
    
    last_state = read_gpio();
    gettimeofday(&last_change, NULL);
    
    while (running) {
        int current_state = read_gpio();
        struct timeval now;
        gettimeofday(&now, NULL);
        
        min_duration = read_min_duration();
        
        if (current_state != last_state) {
            double elapsed = (now.tv_sec - last_change.tv_sec) + 
                           (now.tv_usec - last_change.tv_usec) / 1000000.0;
            
            if (last_state == 0 && elapsed < min_duration) {
                gettimeofday(&last_change, NULL);
            } else {
                last_state = current_state;
                gettimeofday(&last_change, NULL);
                if (current_state == 0) {
                    write_state(current_state, elapsed);
                } else {
                    write_state(current_state, 0);
                }
            }
        } else if (current_state == 0) {
            double elapsed = (now.tv_sec - last_change.tv_sec) + 
                           (now.tv_usec - last_change.tv_usec) / 1000000.0;
            if (elapsed >= min_duration) {
                write_state(current_state, elapsed);
            }
        }
        
        usleep(20000);
    }
    
    cleanup_gpio();
    return 0;
}
EOF

gcc /tmp/rx_gpio_monitor.c -o /tmp/rx_gpio_monitor 2>> "$INSTALL_LOG"
if [ $? -ne 0 ] || [ ! -f /tmp/rx_gpio_monitor ]; then
    cat > /tmp/rx_gpio_monitor.c << 'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/time.h>
#include <signal.h>

#define STATE_FILE "/tmp/rx_gpio_state"
#define CONFIG_FILE "/home/pi/frn-web/data/gpio_config.json"

volatile int running = 1;
double min_duration = 0.5;

double read_min_duration() {
    FILE *fp = fopen(CONFIG_FILE, "r");
    if (!fp) return min_duration;
    char buffer[256];
    size_t n = fread(buffer, 1, sizeof(buffer)-1, fp);
    fclose(fp);
    if (n > 0) {
        buffer[n] = '\0';
        char *p = strstr(buffer, "\"rx_gpio2_duration\"");
        if (p) {
            p = strchr(p, ':');
            if (p) {
                p++;
                double val = strtod(p, NULL);
                if (val >= 0 && val <= 2.0) return val;
            }
        }
    }
    return min_duration;
}

void handle_signal(int sig) { running = 0; }

void write_state(int pin_state, double duration) {
    FILE *fp = fopen(STATE_FILE, "w");
    if (fp) {
        fprintf(fp, "%d %.3f\n", pin_state, duration);
        fflush(fp);
        fclose(fp);
    }
}

int main() {
    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);
    write_state(1, 0);
    while (running) {
        min_duration = read_min_duration();
        usleep(50000);
    }
    return 0;
}
EOF
    gcc /tmp/rx_gpio_monitor.c -o /tmp/rx_gpio_monitor 2>> "$INSTALL_LOG"
fi

if [ -f /tmp/rx_gpio_monitor ]; then
    sudo cp /tmp/rx_gpio_monitor /usr/local/bin/
    sudo chmod +x /usr/local/bin/rx_gpio_monitor
    sudo chown pi:pi /usr/local/bin/rx_gpio_monitor
    rm /tmp/rx_gpio_monitor.c /tmp/rx_gpio_monitor 2>/dev/null
    echo -e "${GREEN}${CHECK_MARK}${NC}"
else
    echo -e "${YELLOW}${WARN_MARK} (пропущено, GPIO недоступен)${NC}"
fi

echo -n "[12/15] Создание server.js... "
cat > /home/pi/frn-web/server.js << 'SERVER'
const express = require('express');
const fs = require('fs').promises;
const { exec, execSync, spawn } = require('child_process');
const os = require('os');
const path = require('path');
const WebSocket = require('ws');
const http = require('http');
const fsSync = require('fs');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server, path: '/ws' });

app.use(express.json());
app.use(express.static('public'));

let cfg;
try {
    cfg = JSON.parse(fsSync.readFileSync('/home/pi/frn-web/data/frn_path.json', 'utf8'));
} catch(e) {
    cfg = { frn_dir: '/home/pi/AFRNClient', frn_binary: '/home/pi/AFRNClient/AFRNClient', frn_config: '/home/pi/AFRNClient/frnconsole.cfg.unix' };
}

const FRN_DIR = cfg.frn_dir;
const FRN_CONFIG = cfg.frn_config;
const FRN_LOG = path.join(FRN_DIR, 'frnclient.log');
const FRN_BINARY = cfg.frn_binary;
const GPIO_CONFIG = '/home/pi/frn-web/data/gpio_config.json';
const GPIO_STATE = '/tmp/rx_gpio_state';
const PORT = 3000;

let gpioMonitor = null;

function readConfigParams() {
    try {
        const content = fsSync.readFileSync(FRN_CONFIG, 'utf8');
        const lines = content.split('\n');
        let email = 'не указан', callsign = 'не указан', city = 'не указан', frequency = 'не указана';
        for (const line of lines) {
            if (line.startsWith('EMailAddress=')) email = line.substring(13).trim();
            if (line.startsWith('Callsign=')) callsign = line.substring(9).trim();
            if (line.startsWith('City=')) city = line.substring(5).trim();
            if (line.startsWith('BandChannel=')) frequency = line.substring(12).trim();
        }
        return { email, callsign, city, frequency };
    } catch(e) { return { email: 'ошибка', callsign: 'ошибка', city: 'ошибка', frequency: 'ошибка' }; }
}

function readGpioConfig() {
    try { return JSON.parse(fsSync.readFileSync(GPIO_CONFIG, 'utf8')); }
    catch(e) { return { rx_gpio2_duration: 0.5, gpio_pin: 2 }; }
}

function writeGpioConfig(config) {
    try { config.last_update = new Date().toISOString(); fsSync.writeFileSync(GPIO_CONFIG, JSON.stringify(config, null, 2)); return true; }
    catch(e) { return false; }
}

function readRxGpioState() {
    try {
        if (fsSync.existsSync(GPIO_STATE)) {
            const content = fsSync.readFileSync(GPIO_STATE, 'utf8').trim();
            const parts = content.split(' ');
            if (parts.length >= 1) {
                const state = parseInt(parts[0]);
                const duration = parts.length >= 2 ? parseFloat(parts[1]) : 0;
                return { active: state === 0, duration: duration, timestamp: Date.now() };
            }
        }
    } catch(e) {}
    return { active: false, duration: 0, timestamp: Date.now() };
}

function startGpioMonitor() {
    if (gpioMonitor) gpioMonitor.kill();
    if (!fsSync.existsSync('/usr/local/bin/rx_gpio_monitor')) return;
    gpioMonitor = spawn('/usr/local/bin/rx_gpio_monitor', [], { stdio: 'ignore' });
    gpioMonitor.on('error', () => setTimeout(startGpioMonitor, 10000));
    gpioMonitor.on('exit', (code) => { gpioMonitor = null; if (code !== 0) setTimeout(startGpioMonitor, 5000); });
}

function stopGpioMonitor() { if (gpioMonitor) { gpioMonitor.kill(); gpioMonitor = null; } }

const info = readConfigParams();
const gpioCfg = readGpioConfig();

console.log('\n============================================================');
console.log('🔷 FRN WEB CONTROL v4.3.0');
console.log('🔷 For RW6HHL 2026');
console.log('🔷 Путь к FRN: ' + FRN_BINARY);
console.log('🔷 RX GPIO2 COS: активен, мин. длительность ' + gpioCfg.rx_gpio2_duration + ' сек');
console.log('============================================================');
console.log('📧 Линк: ' + info.email);
console.log('📻 Позывной: ' + info.callsign);
console.log('🏙️ Город: ' + info.city);
console.log('📡 Частота: ' + info.frequency);
console.log('============================================================\n');

wss.on('connection', (ws) => {
    try { ws.send(execSync(`tail -30 ${FRN_LOG} 2>/dev/null || echo ""`).toString()); } catch(e) {}
    ws.send(JSON.stringify({ type: 'gpio', state: readRxGpioState() }));
    const interval = setInterval(() => {
        exec(`tail -1 ${FRN_LOG} 2>/dev/null`, (err, stdout) => { if (!err && stdout && stdout.trim()) ws.send(stdout); });
        ws.send(JSON.stringify({ type: 'gpio', state: readRxGpioState() }));
    }, 2000);
    ws.on('close', () => clearInterval(interval));
});

function getLocalIP() {
    const nets = os.networkInterfaces();
    for (const name of Object.keys(nets)) {
        for (const net of nets[name]) {
            if (net.family === 'IPv4' && !net.internal) return net.address;
        }
    }
    return '127.0.0.1';
}

app.get('/api/status', (req, res) => res.json({ status: 'ok', version: '4.3.0' }));
app.get('/api/link-info', (req, res) => res.json(readConfigParams()));
app.get('/api/gpio/config', (req, res) => res.json(readGpioConfig()));
app.get('/api/gpio/state', (req, res) => res.json(readRxGpioState()));

app.post('/api/gpio/config', (req, res) => {
    const { rx_gpio2_duration } = req.body;
    if (rx_gpio2_duration === undefined || rx_gpio2_duration < 0 || rx_gpio2_duration > 2.0) {
        return res.status(400).json({ error: 'Длительность от 0 до 2 секунд' });
    }
    const config = readGpioConfig();
    config.rx_gpio2_duration = parseFloat(rx_gpio2_duration);
    if (writeGpioConfig(config)) {
        stopGpioMonitor();
        setTimeout(startGpioMonitor, 500);
        res.json({ success: true, config });
    } else { res.status(500).json({ error: 'Ошибка сохранения' }); }
});

app.get('/api/config', async (req, res) => {
    try {
        const config = await fs.readFile(FRN_CONFIG, 'utf8');
        const lines = config.split('\n');
        let server = 'frn.hamcom.ru', port = '9010', network = 'Regions';
        for (const line of lines) {
            if (line.startsWith('ServerAddress=')) server = line.split('=')[1].trim();
            if (line.startsWith('ServerPort=')) port = line.split('=')[1].trim();
            if (line.startsWith('Network=')) network = line.split('=')[1].trim();
        }
        const info = readConfigParams();
        res.json({ server, port, network, callsign: info.callsign, city: info.city, frequency: info.frequency, email: info.email });
    } catch(e) {
        const info = readConfigParams();
        res.json({ server: 'frn.hamcom.ru', port: '9010', network: 'Regions', callsign: info.callsign, city: info.city, frequency: info.frequency, email: info.email });
    }
});

app.post('/api/config', async (req, res) => {
    const { server, port, network } = req.body;
    try {
        let config = await fs.readFile(FRN_CONFIG, 'utf8');
        let lines = config.split('\n');
        let foundServer = false, foundPort = false, foundNetwork = false;
        lines = lines.map(line => {
            if (line.startsWith('ServerAddress=')) { foundServer = true; return `ServerAddress=${server}`; }
            if (line.startsWith('ServerPort=')) { foundPort = true; return `ServerPort=${port}`; }
            if (line.startsWith('Network=')) { foundNetwork = true; return `Network=${network}`; }
            return line;
        });
        if (!foundServer) lines.push(`ServerAddress=${server}`);
        if (!foundPort) lines.push(`ServerPort=${port}`);
        if (!foundNetwork) lines.push(`Network=${network}`);
        await fs.writeFile(FRN_CONFIG, lines.join('\n'));
        res.json({ success: true });
    } catch(e) { res.status(500).json({ error: e.message }); }
});

app.post('/api/frn/:action', (req, res) => {
    const action = req.params.action;
    if (action === 'status') {
        exec('pgrep -f "AFRNClient|FRNClient"', (err, stdout) => res.json({ running: stdout.trim().length > 0 }));
    } else if (action === 'start') {
        exec(`cd ${FRN_DIR} && sudo -n ${FRN_BINARY} daemon frnconsole.cfg.unix > /dev/null 2>&1 &`, () => res.json({ status: 'started' }));
    } else if (action === 'stop') {
        exec('sudo -n pkill -f "AFRNClient|FRNClient"', () => res.json({ status: 'stopped' }));
    } else if (action === 'restart') {
        exec('sudo -n pkill -f "AFRNClient|FRNClient"', () => {
            setTimeout(() => { exec(`cd ${FRN_DIR} && sudo -n ${FRN_BINARY} daemon frnconsole.cfg.unix > /dev/null 2>&1 &`, () => res.json({ status: 'restarted' })); }, 3000);
        });
    } else { res.status(404).json({ error: 'Not found' }); }
});

app.get('/api/log', async (req, res) => {
    try { res.send(await fs.readFile(FRN_LOG, 'utf8')); }
    catch(e) { res.send('Лог пуст'); }
});

server.listen(PORT, '0.0.0.0', () => {
    console.log(`🌐 Локально: http://localhost:${PORT}`);
    console.log(`🌐 В сети: http://${getLocalIP()}:${PORT}`);
    startGpioMonitor();
});

process.on('SIGINT', () => { stopGpioMonitor(); process.exit(); });
process.on('SIGTERM', () => { stopGpioMonitor(); process.exit(); });
SERVER
echo -e "${GREEN}${CHECK_MARK}${NC}"

echo -n "[13/15] Создание веб-интерфейса с РАСШИРЕННЫМ СПИСКОМ СЕРВЕРОВ... "
cat > /home/pi/frn-web/public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FRN Link Control v4.3.0 - Расширенная версия</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; background: linear-gradient(135deg, #1a2639 0%, #2c3e50 100%); min-height: 100vh; padding: 15px; color: #333; }
        .container { max-width: 700px; margin: 0 auto; }
        .header { background: white; border-radius: 20px; padding: 20px; margin-bottom: 20px; box-shadow: 0 15px 30px rgba(0,0,0,0.2); text-align: center; }
        .header h1 { color: #1a2639; font-size: 1.8rem; margin-bottom: 5px; }
        .version-badge { background: linear-gradient(135deg, #3498db, #2980b9); color: white; padding: 4px 12px; border-radius: 20px; font-size: 0.8rem; display: inline-block; margin-bottom: 8px; }
        .owner-info { font-size: 0.85rem; color: #7f8c8d; margin-bottom: 8px; }
        .email { font-size: 0.85rem; color: #3498db; background: #ebf5ff; padding: 6px 15px; border-radius: 20px; word-break: break-all; margin: 8px 0; font-weight: 500; }
        .window-id { background: #f0f2f5; padding: 4px 12px; border-radius: 15px; font-size: 0.7rem; color: #64748b; display: inline-block; font-family: monospace; }
        .link-info { background: linear-gradient(135deg, #3498db, #2c3e50); color: white; border-radius: 20px; padding: 15px; margin-bottom: 20px; }
        .link-badge { background: rgba(255,255,255,0.2); padding: 4px 15px; border-radius: 20px; display: inline-block; margin-bottom: 12px; font-weight: 600; }
        .link-info-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 8px; }
        .info-item { background: rgba(255,255,255,0.15); padding: 8px; border-radius: 12px; text-align: center; }
        .info-item .label { font-size: 0.65rem; opacity: 0.9; text-transform: uppercase; }
        .info-item .value { font-size: 0.9rem; font-weight: 700; }
        .status-bar { background: white; border-radius: 15px; padding: 12px 15px; margin-bottom: 20px; display: flex; justify-content: space-between; align-items: center; }
        .status-left { display: flex; align-items: center; gap: 8px; }
        .status-led { width: 10px; height: 10px; border-radius: 50%; background: #ef4444; }
        .status-led.active { background: #10b981; box-shadow: 0 0 10px #10b981; }
        .status-text { font-weight: 600; font-size: 0.9rem; }
        .current-network { background: #eef2f6; padding: 4px 12px; border-radius: 20px; font-size: 0.8rem; font-weight: 600; color: #1a2639; }
        .section { background: white; border-radius: 20px; padding: 18px; margin-bottom: 20px; }
        .section-title { font-size: 1rem; margin-bottom: 15px; display: flex; align-items: center; gap: 6px; font-weight: 600; border-bottom: 1px solid #e5e7eb; padding-bottom: 10px; cursor: pointer; }
        .section-title:hover { opacity: 0.7; }
        .collapse-icon { font-size: 1rem; transition: transform 0.3s; }
        .collapse-icon.collapsed { transform: rotate(-90deg); }
        .section-content { transition: all 0.3s ease; overflow: hidden; }
        .section-content.collapsed { display: none; }
        .gpio-indicator { background: #f0f9ff; border: 1px solid #bae6fd; border-radius: 12px; padding: 10px; margin-bottom: 15px; display: flex; justify-content: space-between; align-items: center; }
        .gpio-led { width: 12px; height: 12px; border-radius: 50%; background: #9ca3af; display: inline-block; margin-right: 8px; }
        .gpio-led.active { background: #f97316; box-shadow: 0 0 10px #f97316; animation: pulse 1s infinite; }
        @keyframes pulse { 0% { opacity: 1; } 50% { opacity: 0.7; } 100% { opacity: 1; } }
        .gpio-duration { background: #f3f4f6; padding: 12px; border-radius: 12px; margin-top: 10px; }
        .gpio-duration label { display: block; color: #4b5563; font-size: 0.75rem; font-weight: 600; margin-bottom: 8px; text-transform: uppercase; }
        .gpio-duration input { width: 100%; padding: 8px 12px; border: 1px solid #e2e8f0; border-radius: 12px; }
        .duration-value { margin-left: 8px; font-weight: 600; color: #3498db; }
        .row { margin-bottom: 12px; }
        .row label { display: block; color: #4b5563; font-size: 0.75rem; font-weight: 600; margin-bottom: 4px; text-transform: uppercase; }
        .row select { width: 100%; padding: 8px 12px; border: 1px solid #e2e8f0; border-radius: 12px; background: #f8fafc; cursor: pointer; }
        .btn-group { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 15px; }
        .btn { flex: 1; min-width: 90px; padding: 8px 10px; border: none; border-radius: 12px; font-size: 0.8rem; font-weight: 600; cursor: pointer; color: white; display: flex; align-items: center; justify-content: center; gap: 4px; }
        .btn-red { background: linear-gradient(135deg, #ef4444, #dc2626); }
        .btn-blue { background: linear-gradient(135deg, #3b82f6, #2563eb); }
        .btn-green { background: linear-gradient(135deg, #10b981, #059669); }
        .btn-orange { background: linear-gradient(135deg, #f97316, #ea580c); }
        .btn-purple { background: linear-gradient(135deg, #8b5cf6, #6d28d9); }
        .footer { text-align: center; color: rgba(255,255,255,0.7); font-size: 0.75rem; margin-top: 20px; padding: 12px; background: rgba(0,0,0,0.3); border-radius: 15px; }
        .toast { position: fixed; bottom: 20px; right: 20px; background: white; padding: 10px 20px; border-radius: 12px; display: none; align-items: center; gap: 8px; border-left: 4px solid #10b981; z-index: 1000; }
        .toast.error { border-left-color: #ef4444; }
        .toast.show { display: flex; }
        @media (max-width:600px) { .btn-group { flex-direction: column; } .btn { width: 100%; } }
        select option { font-size: 0.8rem; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="version-badge">v4.3.0</div>
            <h1>FRN Link Control</h1>
            <div class="owner-info">RW6HHL 2026</div>
            <div class="email" id="linkEmail">Загрузка...</div>
            <div class="window-id" id="windowInfo">Загрузка...</div>
        </div>
        <div class="link-info">
            <div style="text-align:center"><span class="link-badge" id="linkCallsign">Загрузка...</span></div>
            <div class="link-info-grid">
                <div class="info-item"><div class="label">📡 ЧАСТОТА</div><div class="value" id="linkFrequency">---</div></div>
                <div class="info-item"><div class="label">🏙️ ГОРОД</div><div class="value" id="linkCity">---</div></div>
                <div class="info-item"><div class="label">🔌 ПОРТ</div><div class="value" id="linkPort">---</div></div>
                <div class="info-item"><div class="label">🚪 КОМНАТА</div><div class="value" id="linkRoom">---</div></div>
            </div>
        </div>
        <div class="status-bar">
            <div class="status-left"><span class="status-led" id="statusLed"></span><span class="status-text" id="statusText">Проверка...</span></div>
            <div class="current-network" id="currentNetwork">-</div>
        </div>
        <div class="section">
            <div class="section-title" onclick="toggleGpioSection()"><span class="collapse-icon" id="gpioCollapseIcon">▼</span><span>🔌 RX GPIO2 COS - НАСТРОЙКИ ВХОДНОГО СИГНАЛА</span></div>
            <div class="section-content" id="gpioSectionContent">
                <div class="gpio-indicator"><span><span class="gpio-led" id="gpioLed"></span><span id="gpioStatusText">RX сигнал: ожидание</span></span><span id="gpioDuration" style="font-size:0.8rem;color:#64748b;">0.0 сек</span></div>
                <div class="gpio-duration"><label>🕒 Минимальная длительность сигнала (сек) <span class="duration-value" id="durationValue">0.5</span></label><input type="range" id="rxDuration" min="0" max="2.0" step="0.1" value="0.5"><div style="display:flex; justify-content:space-between; margin-top:5px; font-size:0.7rem; color:#94a3b8;"><span>0.0 сек</span><span>1.0 сек</span><span>2.0 сек</span></div></div>
                <button class="btn btn-purple" onclick="saveGpioConfig()" style="width:100%; margin-top:10px">💾 СОХРАНИТЬ НАСТРОЙКИ RX</button>
                <div style="margin-top:8px; font-size:0.75rem; color:#64748b; text-align:center;">⚡ Все сигналы короче установленной длительности будут игнорироваться</div>
            </div>
        </div>
        <div class="section">
            <div class="section-title"><span>⚙️</span> НАСТРОЙКИ ЛИНКА</div>
            <div class="row"><label>🖥️ СЕРВЕР FRN</label><select id="server" onchange="updateRooms()"></select></div>
            <div class="row"><label>🚪 КОМНАТА</label><select id="network"></select></div>
            <div class="btn-group"><button class="btn btn-red" onclick="disconnectFRN()" id="disconnectBtn">⏹️ РАЗЪЕДИНИТЬ</button><button class="btn btn-blue" onclick="saveConfig()" id="saveBtn1">💾 СОХРАНИТЬ</button><button class="btn btn-green" onclick="connectFRN()" id="connectBtn">▶️ СОЕДИНИТЬ</button><button class="btn btn-orange" onclick="restartFRN()" id="restartBtn">🔄 ПЕРЕГРУЗИТЬ</button></div>
        </div>
        <div class="footer"><div>🔷 FRN Web Control v4.3.0 | RW6HHL 2026 | RX GPIO2 COS Control</div><div style="margin-top:4px; font-size:0.7rem;">Линк: <span id="footerEmail"></span></div></div>
    </div>
    <div id="toast" class="toast"><span id="toastIcon">✅</span><span id="toastMessage">Сообщение</span></div>
    <script>
        const windowId = 'win_' + Math.random().toString(36).substr(2, 9);
        const sessionId = Date.now().toString(36) + Math.random().toString(36).substr(2);
        document.getElementById('windowInfo').innerHTML = `🆔 ${windowId.substr(0,8)} | ${sessionId.substr(0,6)}`;
        
        // ============================================================
        // РАСШИРЕННЫЙ СПИСОК СЕРВЕРОВ FRN И ИХ КОМНАТ
        // ============================================================
        const SERVERS_LIST = [
            { name: "01.lpd-net.ru", port: "10024", rooms: ["Dīnīyē", "Net07"] },
            { name: "016.ipv6.lpd-net.ru", port: "10044", rooms: ["Dīnīyē", "Net07"] },
            { name: "02.lpd-net.ru", port: "10034", rooms: ["Test", "Regions", "Rus26", "Rus05", "Rus50", "Rus64", "Rus76", "Rus95"] },
            { name: "026.ipv6.lpd-net.ru", port: "10044", rooms: ["Test", "Regions", "Rus26"] },
            { name: "1a-funkfeuer.org", port: "10024", rooms: ["Berghütte", "FM-Funknetz-Link"] },
            { name: "2a0a:9300:d1::16a3", port: "10034", rooms: ["Dīnīyē", "Net07"] },
            { name: "Brazil-FRN.dvbr.net", port: "10024", rooms: ["Test", "Regions", "FRN"] },
            { name: "frn.hamcom.ru", port: "9010", rooms: ["Test", "Regions", "Rus26", "Rus05", "Rus50", "Rus64", "Rus76", "Rus95", "Privat"] },
            { name: "frn.r5vaz.ru", port: "10024", rooms: ["Scanner", "Repiter", "Gubernia33"] },
            { name: "frn55.ru", port: "10024", rooms: ["Test", "Regions", "FRN", "Rus26"] },
            { name: "kavkaz.qrz.ru", port: "10024", rooms: ["Test", "Kavkaz", "FRN", "SVXREFLECTOR", "NET1", "NET2", "NET3"] },
            { name: "r3pij.ru", port: "10024", rooms: ["NMSK", "FRN"] },
            { name: "r9fda.ru", port: "10024", rooms: ["FRN", "FREE"] },
            { name: "xn--02-bmclt.lpd-net.ru", port: "10024", rooms: ["Test", "Regions", "FRN"] }
        ];
        
        // Создание объекта ROOMS для быстрого доступа
        const ROOMS = {};
        SERVERS_LIST.forEach(server => {
            ROOMS[`${server.name}:${server.port}`] = server.rooms;
        });
        
        // Заполнение select серверов
        const serverSelect = document.getElementById('server');
        SERVERS_LIST.forEach(server => {
            const option = document.createElement('option');
            option.value = `${server.name}:${server.port}`;
            option.textContent = `🌐 ${server.name}:${server.port}`;
            serverSelect.appendChild(option);
        });
        
        let isActionInProgress = false, ws = null, gpioSectionCollapsed = false;
        
        function toggleGpioSection() { 
            const c = document.getElementById('gpioSectionContent'), i = document.getElementById('gpioCollapseIcon'); 
            gpioSectionCollapsed = !gpioSectionCollapsed; 
            if(gpioSectionCollapsed){ 
                c.classList.add('collapsed'); 
                i.classList.add('collapsed'); 
                i.innerHTML = '▶'; 
            } else { 
                c.classList.remove('collapsed'); 
                i.classList.remove('collapsed'); 
                i.innerHTML = '▼'; 
            } 
            localStorage.setItem('gpioSectionCollapsed', gpioSectionCollapsed); 
        }
        
        function showToast(m, e=false){ 
            let t=document.getElementById('toast'); 
            document.getElementById('toastIcon').textContent=e?'❌':'✅'; 
            document.getElementById('toastMessage').textContent=m; 
            t.classList.toggle('error',e); 
            t.classList.add('show'); 
            setTimeout(()=>t.classList.remove('show'),2000); 
        }
        
        function setButtonsLoading(l){ 
            isActionInProgress=l; 
            ['disconnectBtn','saveBtn1','connectBtn','restartBtn'].forEach(id=>{ 
                let b=document.getElementById(id); 
                if(b) b.disabled=l; 
            }); 
        }
        
        function updateRooms(){ 
            let s=document.getElementById('server').value, n=document.getElementById('network'), cur=n.value; 
            if(ROOMS[s]) {
                n.innerHTML=ROOMS[s].map(r=>`<option value="${r}" ${r===cur?'selected':''}>${r}</option>`).join('');
            } else {
                n.innerHTML='<option value="Test">Test</option><option value="Regions">Regions</option>';
            }
        }
        
        function initWebSocket(){ 
            let p=location.protocol==='https:'?'wss:':'ws:'; 
            ws=new WebSocket(`${p}//${location.host}/ws`); 
            ws.onmessage=e=>{ 
                try{ 
                    let d=JSON.parse(e.data); 
                    if(d.type==='gpio') updateGpioIndicator(d.state); 
                } catch(e){} 
            }; 
            ws.onclose=()=>setTimeout(initWebSocket,3000); 
        }
        
        function updateGpioIndicator(s){ 
            let l=document.getElementById('gpioLed'), t=document.getElementById('gpioStatusText'), d=document.getElementById('gpioDuration'); 
            if(s.active){ 
                l.className='gpio-led active'; 
                t.innerHTML='📻 RX сигнал: АКТИВЕН'; 
                d.innerHTML=s.duration.toFixed(1)+' сек'; 
            } else { 
                l.className='gpio-led'; 
                t.innerHTML='💤 RX сигнал: ожидание'; 
                d.innerHTML='0.0 сек'; 
            } 
        }
        
        async function loadGpioConfig(){ 
            let r=await fetch('/api/gpio/config'), c=await r.json(), s=document.getElementById('rxDuration'), v=document.getElementById('durationValue'); 
            s.value=c.rx_gpio2_duration; 
            v.innerHTML=c.rx_gpio2_duration.toFixed(1)+' сек'; 
            s.oninput=()=>v.innerHTML=s.value+' сек'; 
        }
        
        async function saveGpioConfig(){ 
            let d=parseFloat(document.getElementById('rxDuration').value), r=await fetch('/api/gpio/config',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({rx_gpio2_duration:d})}), data=await r.json(); 
            if(data.success) showToast('Настройки RX GPIO2 сохранены'); 
            else showToast('Ошибка сохранения',true); 
        }
        
        async function loadLinkInfo(){ 
            let r=await fetch('/api/link-info'), i=await r.json(); 
            document.getElementById('linkEmail').innerHTML=`📧 ${i.email||'Неизвестно'}`; 
            document.getElementById('footerEmail').innerHTML=i.email||'???'; 
            document.getElementById('linkCallsign').innerHTML=`📻 ${i.callsign||'???'}`; 
            document.getElementById('linkFrequency').innerHTML=i.frequency||'---'; 
            document.getElementById('linkCity').innerHTML=i.city||'---'; 
        }
        
        async function loadConfig(){ 
            let r=await fetch('/api/config'), d=await r.json(), sv=d.server+':'+d.port, s=document.getElementById('server'); 
            // Проверяем существует ли такой сервер в списке
            let serverExists = false;
            for(let i=0; i<s.options.length; i++) {
                if(s.options[i].value === sv) {
                    s.selectedIndex = i;
                    serverExists = true;
                    break;
                }
            }
            if(!serverExists && sv) {
                // Добавляем текущий сервер если его нет в списке
                let option = document.createElement('option');
                option.value = sv;
                option.textContent = `🌐 ${sv}`;
                s.appendChild(option);
                s.value = sv;
            }
            updateRooms(); 
            document.getElementById('network').value=d.network||'Regions'; 
            document.getElementById('currentNetwork').innerHTML=d.network||'-'; 
            document.getElementById('linkRoom').innerHTML=d.network||'---'; 
            document.getElementById('linkPort').innerHTML=d.port||'---'; 
        }
        
        async function saveConfig(){ 
            if(isActionInProgress) return; 
            try{ 
                setButtonsLoading(true); 
                let[s,p]=document.getElementById('server').value.split(':'); 
                let r=await fetch('/api/config',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({server:s,port:p,network:document.getElementById('network').value})}); 
                let data=await r.json(); 
                if(data.success){ 
                    showToast('Конфигурация сохранена'); 
                    await loadConfig(); 
                } else showToast('Ошибка сохранения',true); 
            } catch(e){ 
                showToast('Ошибка сохранения',true); 
            } finally{ 
                setButtonsLoading(false); 
            } 
        }
        
        async function connectFRN(){ 
            if(isActionInProgress) return; 
            try{ 
                setButtonsLoading(true); 
                await saveConfig(); 
                let r=await fetch('/api/frn/start',{method:'POST'}), d=await r.json(); 
                if(d.status==='started') showToast('FRNClient запущен'); 
                else showToast('Ошибка запуска',true); 
                await updateStatus(); 
            } catch(e){ 
                showToast('Ошибка запуска',true); 
            } finally{ 
                setButtonsLoading(false); 
            } 
        }
        
        async function disconnectFRN(){ 
            if(isActionInProgress) return; 
            try{ 
                setButtonsLoading(true); 
                let r=await fetch('/api/frn/stop',{method:'POST'}), d=await r.json(); 
                if(d.status==='stopped') showToast('FRNClient остановлен'); 
                await updateStatus(); 
            } catch(e){ 
                showToast('Ошибка остановки',true); 
            } finally{ 
                setButtonsLoading(false); 
            } 
        }
        
        async function restartFRN(){ 
            if(isActionInProgress) return; 
            try{ 
                setButtonsLoading(true); 
                await saveConfig(); 
                let r=await fetch('/api/frn/restart',{method:'POST'}), d=await r.json(); 
                if(d.status==='restarted') showToast('FRNClient перезапущен'); 
                else if(d.status==='error') showToast('Ошибка перезапуска',true); 
                setTimeout(updateStatus,3000); 
            } catch(e){ 
                showToast('Ошибка перезапуска',true); 
            } finally{ 
                setButtonsLoading(false); 
            } 
        }
        
        async function updateStatus(){ 
            try{ 
                let r=await fetch('/api/frn/status',{method:'POST'}), d=await r.json(), l=document.getElementById('statusLed'), t=document.getElementById('statusText'); 
                if(d.running){ 
                    l.className='status-led active'; 
                    t.textContent='Подключен'; 
                } else { 
                    l.className='status-led'; 
                    t.textContent='Отключен'; 
                } 
            } catch(e){ 
                console.error(e); 
            } 
        }
        
        document.addEventListener('DOMContentLoaded',()=>{ 
            loadLinkInfo(); 
            loadConfig(); 
            loadGpioConfig(); 
            updateStatus(); 
            initWebSocket(); 
            setInterval(updateStatus,5000); 
            let s=localStorage.getItem('gpioSectionCollapsed'); 
            if(s==='true'){ 
                gpioSectionCollapsed=true; 
                document.getElementById('gpioSectionContent').classList.add('collapsed'); 
                document.getElementById('gpioCollapseIcon').classList.add('collapsed'); 
                document.getElementById('gpioCollapseIcon').innerHTML='▶'; 
            } 
        });
    </script>
</body>
</html>
EOF
echo -e "${GREEN}${CHECK_MARK}${NC}"

echo -n "[14/15] Создание скриптов... "
sudo tee /usr/local/bin/frn-web-control > /dev/null << 'EOF'
#!/bin/bash
case "$1" in
    start) sudo systemctl start frn-web.service; echo "✅ Сервис запущен" ;;
    stop) sudo systemctl stop frn-web.service; echo "⏹️ Сервис остановлен" ;;
    restart) sudo systemctl restart frn-web.service; echo "🔄 Сервис перезапущен" ;;
    status) sudo systemctl status frn-web.service --no-pager ;;
    logs) sudo journalctl -u frn-web.service -f ;;
    ip) echo "http://$(hostname -I | awk '{print $1}'):3000" ;;
    fix) sudo chown -R pi:pi /home/pi/frn-web; sudo systemctl restart frn-web.service; echo "✅ Права исправлены" ;;
    gpio) cat /tmp/rx_gpio_state 2>/dev/null || echo "GPIO не активен" ;;
    *) echo "Использование: frn-web-control {start|stop|restart|status|logs|ip|fix|gpio}" ;;
esac
EOF
sudo chmod +x /usr/local/bin/frn-web-control

sudo tee /usr/local/bin/switch_frn_room.sh > /dev/null << 'EOF'
#!/bin/bash
ROOM="$1"
if [ -z "$ROOM" ]; then echo "Использование: switch_frn_room.sh <ROOM>"; exit 1; fi
CONFIG=$(grep -o '"frn_config":"[^"]*"' /home/pi/frn-web/data/frn_path.json 2>/dev/null | cut -d'"' -f4)
[ -z "$CONFIG" ] && CONFIG="/home/pi/AFRNClient/frnconsole.cfg.unix"
[ ! -f "$CONFIG" ] && { echo "Конфиг не найден"; exit 1; }
cp "$CONFIG" "${CONFIG}.backup"
if grep -q "^Network=" "$CONFIG"; then sed -i "s/^Network=.*/Network=$ROOM/" "$CONFIG"; else echo "Network=$ROOM" >> "$CONFIG"; fi
curl -s -X POST http://localhost:3000/api/frn/restart > /dev/null
echo "✅ Переключено в $ROOM"
EOF
sudo chmod +x /usr/local/bin/switch_frn_room.sh
echo -e "${GREEN}${CHECK_MARK}${NC}"

echo -n "[15/15] Настройка автозапуска... "
sudo tee /etc/systemd/system/frn-web.service > /dev/null << EOF
[Unit]
Description=FRN Web Control v4.3.0
After=network.target
[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=/home/pi/frn-web
ExecStart=/usr/bin/node /home/pi/frn-web/server.js
Restart=always
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable frn-web.service > /dev/null 2>&1
sudo systemctl start frn-web.service
sleep 2
echo -e "${GREEN}${CHECK_MARK}${NC}"

# Финальная проверка
IP=$(hostname -I | awk '{print $1}')
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${ROCKET_MARK} УСТАНОВКА FRN WEB CONTROL v4.3.0 ЗАВЕРШЕНА!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${WEB_MARK} Веб-интерфейс: ${BLUE}http://$IP:3000${NC}"
echo -e "${GPIO_MARK} RX GPIO2 COS: АКТИВЕН (0-2 сек, сворачиваемый блок)${NC}"
echo -e "${INFO_MARK} Платформа: ${CYAN}$PLATFORM${NC}"
echo ""
echo -e "${YELLOW}Доступные серверы FRN (${#SERVERS_LIST[@]} шт):${NC}"
for s in "${SERVERS_LIST[@]}"; do
    echo "  • ${s[name]}:${s[port]}"
done
echo ""
echo -e "${YELLOW}Команды:${NC}"
echo "  frn-web-control status  - статус сервиса"
echo "  frn-web-control ip      - показать адрес"
echo "  frn-web-control gpio    - статус RX сигнала"
echo "  switch_frn_room.sh Regions - смена комнаты"
echo ""
echo -e "${GREEN}✅ Установка завершена! Закройте окно.${NC}"
sleep 3