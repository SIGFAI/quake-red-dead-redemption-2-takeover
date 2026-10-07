// Red Dead Redemption 2 Takeover: Quake turned into a dusty Wild West.
// Outlaws replace the army, horses charge, the shotgun is a revolver, grenades are dynamite,
// every kill pays a bounty, and Dead Eye slows time and marks targets for a perfect volley.

.float sigf_cash;        // bounty collected
.float sigf_eye;         // Dead Eye meter 0..100
.float sigf_de_state;    // 0 off, 1 marking, 2 firing
.float sigf_de_t;        // end of the marking phase
.float sigf_de_next;     // next mark or shot
.float sigf_look_at;     // next time the atmosphere is sent to the client
.float sigf_marked;      // monster already has a Dead Eye mark
.float sigf_intro;
.vector sigf_last_org;
.float sigf_still_at;
.float sigf_tw_at;
.float sigf_wall_at;
.float sigf_fill_at;       // demo: next top-up of the gang
.float sigf_de_count;    // marks placed in this Dead Eye

void() sigf_to_arena;
void() sigf_tumbleweed;
float(float fwd, float side) sigf_find_spot;
vector sigf_spot;
entity(string cls, void() spawnfunc, float fwd, float side) sigf_mob;   // defined with the scenery below

// ---------- weapons ----------
float() sigf_bullet_damage =
{
    if (self.classname == "player" && self.weapon == IT_SHOTGUN)
        return 22;                       // the revolver: one heavy bullet
    return 4;
};

void() sigf_revolver_effects =
{
    makevectors(self.v_angle);
    sound(self, CHAN_WEAPON, "sigf/revolver.wav", 1, ATTN_NORM);
    self.effects = self.effects | EF_MUZZLEFLASH;
    particle(self.origin + v_forward * 30 + '0 0 4', v_forward * 90, 192, 24);   // muzzle flash sparks
    particle(self.origin + v_forward * 30 + '0 0 4', v_forward * 60, 232, 16);
    particle(self.origin + v_forward * 34 + '0 0 6', v_forward * 30 + '0 0 20', 8, 14);   // gun smoke
};

// dynamite: a burning fuse that sputters sparks while the stick tumbles
void() sigf_fuse_think =
{
    if (self.owner.classname != "grenade")
    {
        remove(self);
        return;
    }
    setorigin(self, self.owner.origin + '0 0 8');
    particle(self.origin, '0 0 25', 232, 4);
    self.nextthink = time + 0.04;
};

void(entity m) sigf_dynamite_lit =
{
    local entity f;
    m.effects = m.effects | EF_DIMLIGHT;
    f = spawn();
    f.classname = "sigf_fuse";
    f.owner = m;
    f.movetype = MOVETYPE_NONE;
    f.solid = SOLID_NOT;
    setorigin(f, m.origin);
    f.think = sigf_fuse_think;
    f.nextthink = time + 0.04;
};

void(vector org) sigf_dynamite_boom =
{
    particle(org, '0 0 120', 232, 60);       // fireball sparks
    particle(org, '0 0 60', 8, 50);          // dust and smoke
};

// ---------- bounty: cash that flies to the player ----------
void() sigf_cash_touch =
{
    local float n;
    if (other.classname != "player")
        return;
    n = self.cnt;
    other.sigf_cash = other.sigf_cash + n;
    sound(other, CHAN_ITEM, "sigf/cash.wav", 1, ATTN_NORM);
    stuffcmd(other, "bf\n");
    centerprint(other, "BOUNTY +$", ftos(n), "\nTOTAL $", ftos(other.sigf_cash));
    remove(self);
};

void() sigf_cash_think =
{
    local entity p;
    p = find(world, classname, "player");
    if (p && vlen(p.origin - self.origin) < 260)
    {
        self.movetype = MOVETYPE_FLY;
        self.velocity = normalize(p.origin + '0 0 8' - self.origin) * 420;
    }
    self.nextthink = time + 0.1;
    if (time > self.attack_finished)
        self.think = SUB_Remove;
};

void(vector org, float amount) sigf_drop_cash =
{
    local entity o;
    o = spawn();
    o.classname = "sigf_cash";
    o.movetype = MOVETYPE_TOSS;
    o.solid = SOLID_TRIGGER;
    o.cnt = amount;
    setmodel(o, "progs/sigf_cash.spr");
    setsize(o, '-14 -14 0', '14 14 20');
    setorigin(o, org + '0 0 14');
    o.velocity_x = crandom() * 90;
    o.velocity_y = crandom() * 90;
    o.velocity_z = 260;
    o.effects = EF_DIMLIGHT;
    o.touch = sigf_cash_touch;
    o.attack_finished = time + 40;
    o.think = sigf_cash_think;
    o.nextthink = time + 0.5;
};

// ---------- the outlaw: a masked gunslinger on a generated model ----------
// Frames: 0-1 stand, 2-5 walk, 6-9 attack, 10-11 pain, 12-16 death.
void() outlaw_stand1 = [0, outlaw_stand2] { ai_stand(); };
void() outlaw_stand2 = [1, outlaw_stand1] { ai_stand(); };

void() outlaw_walk1 = [2, outlaw_walk2] { ai_walk(4); };
void() outlaw_walk2 = [3, outlaw_walk3] { ai_walk(4); };
void() outlaw_walk3 = [4, outlaw_walk4] { ai_walk(4); };
void() outlaw_walk4 = [5, outlaw_walk1] { ai_walk(4); };

void() outlaw_run1 = [2, outlaw_run2] { ai_run(10); };
void() outlaw_run2 = [3, outlaw_run3] { ai_run(12); };
void() outlaw_run3 = [4, outlaw_run4] { ai_run(10); };
void() outlaw_run4 = [5, outlaw_run1] { ai_run(12); };

void(vector from, vector dir) sigf_tracer =
{
    local float i;
    while (i < 7)
    {
        particle(from + dir * (i * 45), '0 0 0', 192, 3);
        i = i + 1;
    }
};

void() outlaw_fire =
{
    local vector dir, src;
    ai_face();
    sound(self, CHAN_WEAPON, "sigf/revolver.wav", 1, ATTN_NORM);
    self.effects = self.effects | EF_MUZZLEFLASH;
    makevectors(self.angles);
    src = self.origin + '0 0 8';
    particle(src + v_forward * 26, v_forward * 30 + '0 0 20', 8, 14);
    dir = normalize(self.enemy.origin - self.enemy.velocity * 0.1 - src);
    dir = dir + v_right * crandom() * 0.06 + v_up * crandom() * 0.04;
    sigf_tracer(src + v_forward * 20, dir);
    traceline(src, src + dir * 2048, FALSE, self);
    if (trace_fraction != 1.0)
    {
        if (trace_ent.takedamage)
        {
            SpawnBlood(trace_endpos, '0 0 0', 9);
            T_Damage(trace_ent, self, self, 9);
        }
        else
        {
            WriteByte(MSG_BROADCAST, SVC_TEMPENTITY);
            WriteByte(MSG_BROADCAST, TE_GUNSHOT);
            WriteCoord(MSG_BROADCAST, trace_endpos_x);
            WriteCoord(MSG_BROADCAST, trace_endpos_y);
            WriteCoord(MSG_BROADCAST, trace_endpos_z);
        }
    }
};

void() outlaw_atk1 = [6, outlaw_atk2] { ai_face(); };
void() outlaw_atk2 = [7, outlaw_atk3] { ai_face(); };
void() outlaw_atk3 = [8, outlaw_atk4] { ai_face(); outlaw_fire(); };
void() outlaw_atk4 = [9, outlaw_run1] { ai_face(); SUB_CheckRefire(outlaw_atk1); };

void() outlaw_pain1 = [10, outlaw_pain2] { };
void() outlaw_pain2 = [11, outlaw_run1] { ai_pain(2); };

void(entity attacker, float damage) outlaw_pain =
{
    if (self.pain_finished > time)
        return;
    self.pain_finished = time + 0.8;
    sound(self, CHAN_VOICE, "sigf/outlaw_die.wav", 0.6, ATTN_NORM);
    particle(self.origin + '0 0 20', '0 0 40', 73, 20);
    outlaw_pain1();
};

void() outlaw_die1 = [12, outlaw_die2] { };
void() outlaw_die2 = [13, outlaw_die3] { self.solid = SOLID_NOT; };
void() outlaw_die3 = [14, outlaw_die4] { };
void() outlaw_die4 = [15, outlaw_die5] { };
void() outlaw_die5 = [16, outlaw_die5] { };

void() outlaw_die =
{
    if (self.health < -30)
    {
        sound(self, CHAN_VOICE, "player/udeath.wav", 1, ATTN_NORM);
        ThrowHead("progs/h_guard.mdl", self.health);
        ThrowGib("progs/gib1.mdl", self.health);
        ThrowGib("progs/gib2.mdl", self.health);
        ThrowGib("progs/gib3.mdl", self.health);
        return;
    }
    sound(self, CHAN_VOICE, "sigf/outlaw_die.wav", 1, ATTN_NORM);
    outlaw_die1();
};

void() monster_sigf_outlaw =
{
    if (deathmatch)
    {
        remove(self);
        return;
    }
    self.classname = "monster_sigf_outlaw";
    precache_model("progs/sigf_outlaw.mdl");
    precache_model("progs/h_guard.mdl");
    precache_model("progs/gib1.mdl");
    precache_model("progs/gib2.mdl");
    precache_model("progs/gib3.mdl");
    precache_sound("sigf/revolver.wav");
    precache_sound("sigf/yeehaw.wav");
    precache_sound("sigf/outlaw_die.wav");
    precache_sound("player/udeath.wav");
    self.solid = SOLID_SLIDEBOX;
    self.movetype = MOVETYPE_STEP;
    setmodel(self, "progs/sigf_outlaw.mdl");
    setsize(self, '-16 -16 -24', '16 16 40');
    self.health = 60;                    // the army grunt had 30, a revolver bullet does 22
    self.th_stand = outlaw_stand1;
    self.th_walk = outlaw_walk1;
    self.th_run = outlaw_run1;
    self.th_missile = outlaw_atk1;
    self.th_pain = outlaw_pain;
    self.th_die = outlaw_die;
    walkmonster_start();
};

// ---------- the spooked horse: charges and kicks the player across the room ----------
void() horse_stand1 = [0, horse_stand2] { ai_stand(); };
void() horse_stand2 = [1, horse_stand1] { ai_stand(); };

void() horse_walk1 = [2, horse_walk2] { ai_walk(6); };
void() horse_walk2 = [3, horse_walk3] { ai_walk(6); };
void() horse_walk3 = [4, horse_walk4] { ai_walk(6); };
void() horse_walk4 = [5, horse_walk1] { ai_walk(6); };

void() horse_run1 = [2, horse_run2] { ai_run(20); };
void() horse_run2 = [3, horse_run3] { ai_run(22); };
void() horse_run3 = [4, horse_run4] { ai_run(20); };
void() horse_run4 = [5, horse_run1] { ai_run(22); };

void() horse_kick =
{
    local vector d;
    if (!self.enemy)
        return;
    if (vlen(self.enemy.origin - self.origin) > 110)
        return;
    sound(self, CHAN_WEAPON, "sigf/neigh.wav", 1, ATTN_NORM);
    makevectors(self.angles);
    d = normalize(self.enemy.origin - self.origin);
    T_Damage(self.enemy, self, self, 18);
    self.enemy.velocity = d * 420 + '0 0 260';     // a flying kick
    self.enemy.flags = self.enemy.flags - (self.enemy.flags & FL_ONGROUND);
    particle(self.enemy.origin, '0 0 60', 8, 30);
};

void() horse_atk1 = [6, horse_atk2] { ai_face(); };
void() horse_atk2 = [7, horse_atk3] { ai_face(); };
void() horse_atk3 = [8, horse_atk4] { ai_face(); horse_kick(); };
void() horse_atk4 = [9, horse_run1] { ai_face(); };

void() horse_pain1 = [10, horse_pain2] { };
void() horse_pain2 = [11, horse_run1] { };

void(entity attacker, float damage) horse_pain =
{
    if (self.pain_finished > time)
        return;
    self.pain_finished = time + 0.8;
    sound(self, CHAN_VOICE, "sigf/neigh.wav", 1, ATTN_NORM);
    particle(self.origin + '0 0 20', '0 0 40', 73, 20);
    horse_pain1();
};

void() horse_die1 = [12, horse_die2] { };
void() horse_die2 = [13, horse_die3] { self.solid = SOLID_NOT; };
void() horse_die3 = [14, horse_die4] { };
void() horse_die4 = [15, horse_die5] { };
void() horse_die5 = [16, horse_die5] { };

void() horse_die =
{
    if (self.health < -40)
    {
        sound(self, CHAN_VOICE, "player/udeath.wav", 1, ATTN_NORM);
        ThrowGib("progs/gib1.mdl", self.health);
        ThrowGib("progs/gib2.mdl", self.health);
        ThrowGib("progs/gib3.mdl", self.health);
        return;
    }
    sound(self, CHAN_VOICE, "sigf/neigh.wav", 1, ATTN_NORM);
    horse_die1();
};

void() monster_sigf_horse =
{
    if (deathmatch)
    {
        remove(self);
        return;
    }
    self.classname = "monster_sigf_horse";
    precache_model("progs/sigf_horse.mdl");
    precache_model("progs/gib1.mdl");
    precache_model("progs/gib2.mdl");
    precache_model("progs/gib3.mdl");
    precache_sound("sigf/neigh.wav");
    precache_sound("player/udeath.wav");
    self.solid = SOLID_SLIDEBOX;
    self.movetype = MOVETYPE_STEP;
    setmodel(self, "progs/sigf_horse.mdl");
    setsize(self, '-26 -26 -24', '26 26 30');
    self.health = 90;
    self.th_stand = horse_stand1;
    self.th_walk = horse_walk1;
    self.th_run = horse_run1;
    self.th_melee = horse_atk1;
    self.th_pain = horse_pain;
    self.th_die = horse_die;
    walkmonster_start();
};

// ---------- Dead Eye: time slows, targets get marked, then the volley lands ----------
void() sigf_mark_think =
{
    if (!self.enemy || self.enemy.health <= 0)
    {
        remove(self);
        return;
    }
    setorigin(self, self.enemy.origin + '0 0 52');
    self.nextthink = time + 0.03;
};

float() sigf_visible_count =
{
    local entity e;
    local float n;
    e = findradius(self.origin, 1000);
    while (e)
    {
        if ((e.flags & FL_MONSTER) && e.health > 0 && visible(e))
            n = n + 1;
        e = e.chain;
    }
    return n;
};

void() sigf_mark_one =
{
    local entity e, m;
    e = findradius(self.origin, 1000);
    while (e)
    {
        if ((e.flags & FL_MONSTER) && e.health > 0 && !e.sigf_marked && visible(e))
        {
            e.sigf_marked = TRUE;
            m = spawn();
            m.classname = "sigf_mark";
            m.owner = self;
            m.enemy = e;
            m.movetype = MOVETYPE_NONE;
            m.solid = SOLID_NOT;
            setmodel(m, "progs/sigf_mark.spr");
            setorigin(m, e.origin + '0 0 52');
            m.effects = EF_BRIGHTLIGHT;
            m.think = sigf_mark_think;
            m.nextthink = time + 0.03;
            sound(self, CHAN_ITEM, "sigf/cash.wav", 0.7, ATTN_NONE);
            self.sigf_de_count = self.sigf_de_count + 1;
            return;
        }
        e = e.chain;
    }
};

void() sigf_atmosphere =
{
    stuffcmd(self, "fog 0.006 0.78 0.55 0.32 0\n");
    stuffcmd(self, "v_cshift 255 140 60 26\n");
};

void() sigf_deadeye_end =
{
    local entity m;
    cvar_set("host_timescale", "1");
    m = find(world, classname, "sigf_mark");
    while (m)
    {
        m.enemy.sigf_marked = FALSE;
        remove(m);
        m = find(m, classname, "sigf_mark");
    }
    self.sigf_de_state = 0;
    self.sigf_eye = 0;
    sigf_atmosphere();
};

void() sigf_deadeye_try =
{
    if (self.sigf_de_state != 0 || self.health <= 0)
        return;
    if (self.sigf_eye < 100)
    {
        centerprint(self, "Dead Eye is not ready yet\nKill outlaws to fill it");
        return;
    }
    if (sigf_visible_count() < 1)
        return;
    self.sigf_de_state = 1;
    self.sigf_de_count = 0;
    self.sigf_de_t = time + 1.0;
    self.sigf_de_next = time;
    cvar_set("host_timescale", "0.4");
    sound(self, CHAN_VOICE, "sigf/deadeye.wav", 1, ATTN_NONE);
    centerprint(self, "DEAD EYE");
    stuffcmd(self, "fog 0.02 0.55 0.5 0.5 0.3\n");
    stuffcmd(self, "v_cshift 255 255 255 60\n");
};

void(entity v) sigf_de_shoot =
{
    local vector org, tgt, d;
    local float i;
    org = self.origin + '0 0 20';
    tgt = (v.absmin + v.absmax) * 0.5 + '0 0 8';
    d = tgt - org;
    sound(self, CHAN_WEAPON, "sigf/revolver.wav", 1, ATTN_NONE);
    self.effects = self.effects | EF_MUZZLEFLASH;
    while (i < 12)
    {
        particle(org + d * (i / 12), '0 0 0', 192, 4);   // the golden tracer
        i = i + 1;
    }
    particle(tgt, '0 0 40', 73, 16);
    T_Damage(v, self, self, 100);
    v.velocity = v.velocity + normalize(d) * 220 + '0 0 120';
};

// the demo player can wedge itself in a corner: after 3 s without moving or fighting, it is set down in the open
void() sigf_unstick =
{
    if (vlen(self.origin - self.sigf_last_org) > 40 || sigf_visible_count() > 0)
    {
        self.sigf_last_org = self.origin;
        self.sigf_still_at = time;
        return;
    }
    if (time - self.sigf_still_at < 3)
        return;
    self.sigf_still_at = time;
    if (sigf_find_spot(260, 0))
    {
        WriteByte(MSG_BROADCAST, SVC_TEMPENTITY);
        WriteByte(MSG_BROADCAST, TE_TELEPORT);
        WriteCoord(MSG_BROADCAST, self.origin_x);
        WriteCoord(MSG_BROADCAST, self.origin_y);
        WriteCoord(MSG_BROADCAST, self.origin_z);
        setorigin(self, sigf_spot + '0 0 26');
        self.sigf_last_org = self.origin;
    }
};

// staring at a wall with nobody in sight: back to the arena
void() sigf_wallcheck =
{
    makevectors('0 1 0' * self.v_angle_y);
    traceline(self.origin + '0 0 16', self.origin + '0 0 16' + v_forward * 220, TRUE, self);
    if (trace_fraction < 1 && sigf_visible_count() == 0)
        sigf_to_arena();
};

// the demo never lets the arena go quiet: when the gang is nearly dead, more outlaws ride in
void() sigf_keepalive =
{
    local entity e;
    local float n;
    if (time < self.sigf_fill_at || self.sigf_de_state != 0)
        return;
    self.sigf_fill_at = time + 1;
    e = findradius(self.origin, 700);
    while (e)
    {
        if ((e.flags & FL_MONSTER) && e.health > 0)
            n = n + 1;
        e = e.chain;
    }
    if (n >= 2)
        return;
    self.sigf_fill_at = time + 1.5;
    sigf_to_arena();
    if (random() < 0.3)
        sigf_mob("monster_sigf_horse", monster_sigf_horse, 190, 0);
    else
    {
        sigf_mob("monster_sigf_outlaw", monster_sigf_outlaw, 170, -70);
        sigf_mob("monster_sigf_outlaw", monster_sigf_outlaw, 190, 70);
    }
};

void() sigf_player_frame =
{
    local entity m;

    if (self.health <= 0)
        return;
    if (!self.sigf_intro && time > 1)
    {
        self.sigf_intro = TRUE;
        sound(self, CHAN_VOICE, "sigf/twang.wav", 1, ATTN_NONE);
        stuffcmd(self, "play sigf/theme.wav\n");
        stuffcmd(self, "bind q impulse 21\n");
        centerprint(self, "WANTED DEAD OR ALIVE\n$5000 BOUNTY\nShoot outlaws, grab the cash, press Q for Dead Eye");
    }
    if (time > self.sigf_look_at)
    {
        self.sigf_look_at = time + 12;
        if (self.sigf_de_state == 0)
            sigf_atmosphere();
    }
    // the demo player triggers Dead Eye by itself when it is charged and the gang is in sight
    if (SIGF_Mode() != 0 && self.sigf_de_state == 0 && self.sigf_eye >= 100 && sigf_visible_count() >= 2)
        sigf_deadeye_try();

    if (SIGF_Mode() != 0 && time > self.sigf_tw_at)
    {
        self.sigf_tw_at = time + 2.2;
        sigf_tumbleweed();
    }
    if (SIGF_Mode() == 1 && time > 4 && self.sigf_de_state == 0)
        sigf_unstick();
    if (SIGF_Mode() == 1 && time > 5)
    {
        sigf_keepalive();
        if (time > self.sigf_wall_at && self.sigf_de_state == 0)
        {
            self.sigf_wall_at = time + 1;
            sigf_wallcheck();
        }
    }

    if (self.sigf_de_state == 1)
    {
        if (time >= self.sigf_de_next && self.sigf_de_count < 6)
        {
            sigf_mark_one();
            self.sigf_de_next = time + 0.22;
        }
        if (time >= self.sigf_de_t || (self.sigf_de_count >= 6 && time >= self.sigf_de_next))
        {
            self.sigf_de_state = 2;
            self.sigf_de_next = time + 0.12;
        }
    }
    else if (self.sigf_de_state == 2)
    {
        if (time >= self.sigf_de_next)
        {
            m = find(world, classname, "sigf_mark");
            if (!m)
            {
                sigf_deadeye_end();
                return;
            }
            self.sigf_de_next = time + 0.14;
            if (m.enemy.health > 0)
                sigf_de_shoot(m.enemy);
            m.enemy.sigf_marked = FALSE;
            remove(m);
        }
    }
};

void() sigf_mod_frame =
{
    local entity p, oself;
    p = find(world, classname, "player");
    if (!p)
        return;
    oself = self;
    self = p;
    sigf_player_frame();
    self = oself;
};

// ---------- demo scenery: a wanted poster nailed up in front of the player ----------
// A free spot on the floor in front of the player: the distance shrinks until the line of sight is clear.
float(float fwd, float side) sigf_find_spot =
{
    local vector org;
    local float k, off;
    off = 0;
    while (off < 360)
    {
        // 0, +50, -50, +100, -100, ...: the first heading with room wins
        makevectors('0 1 0' * (self.v_angle_y + off));
        k = 1;
        while (k > 0.3)
        {
            org = self.origin + v_forward * fwd * k + v_right * side * k;
            traceline(self.origin + '0 0 8', org + '0 0 8', TRUE, self);
            if (trace_fraction == 1)
            {
                traceline(org + '0 0 40', org - '0 0 300', TRUE, self);
                if (trace_fraction < 1)
                {
                    sigf_spot = trace_endpos;
                    return TRUE;
                }
            }
            k = k - 0.15;
        }
        if (off == 0) off = 50;
        else if (off == 50) off = -50;
        else if (off == -50) off = 100;
        else if (off == 100) off = -100;
        else if (off == -100) off = 150;
        else if (off == 150) off = 180;
        else return FALSE;
    }
    return FALSE;
};

// turn the player toward the most open direction (the map starts in a corner), so the scene has room
void() sigf_face_open =
{
    local float yaw, best, bestyaw;
    yaw = 0;
    while (yaw < 360)
    {
        makevectors('0 1 0' * yaw);
        traceline(self.origin + '0 0 16', self.origin + '0 0 16' + v_forward * 900, TRUE, self);
        if (trace_fraction > best)
        {
            best = trace_fraction;
            bestyaw = yaw;
        }
        yaw = yaw + 15;
    }
    self.v_angle_y = bestyaw;
    self.angles_y = bestyaw;
    self.fixangle = TRUE;
};

// a monster dropped in a clear spot in front of the player
entity(string cls, void() spawnfunc, float fwd, float side) sigf_mob =
{
    local entity e, oself;
    if (!sigf_find_spot(fwd, side))
        return world;
    e = spawn();
    e.classname = cls;
    setorigin(e, sigf_spot + '0 0 28');
    e.angles_y = self.v_angle_y + 180;
    oself = self;
    self = e;
    spawnfunc();
    self = oself;
    if (SIGF_Mode() != 0)
    {
        // the demo player turns to the newcomers
        self.v_angle_y = vectoyaw(e.origin - self.origin);
        self.angles_y = self.v_angle_y;
        self.fixangle = TRUE;
    }
    return e;
};

// ---------- the arena: the most open spot near the start, so the demo always plays in the open ----------
vector sigf_arena;
float sigf_arena_yaw;
float sigf_arena_ok;

void(vector start) sigf_pick_arena =
{
    local float x, y, a, d, score, best;
    local vector o, bo;
    best = -1;
    x = -480;
    while (x <= 480)
    {
        y = -480;
        while (y <= 480)
        {
            o = start + '0 0 8';
            o_x = o_x + x;
            o_y = o_y + y;
            if (pointcontents(o) == CONTENT_EMPTY)
            {
                traceline(start + '0 0 16', o, TRUE, world);
                if (trace_fraction == 1)
                {
                    traceline(o, o - '0 0 80', TRUE, world);
                    if (trace_fraction < 1)
                    {
                        score = 0;
                        a = 0;
                        while (a < 360)
                        {
                            makevectors('0 1 0' * a);
                            traceline(o, o + v_forward * 600, TRUE, world);
                            score = score + trace_fraction;
                            a = a + 45;
                        }
                        if (score > best)
                        {
                            best = score;
                            bo = trace_endpos;
                            bo = o;
                        }
                    }
                }
            }
            y = y + 80;
        }
        x = x + 80;
    }
    if (best < 0)
        return;
    sigf_arena = bo;
    // face the longest open direction
    best = 0;
    a = 0;
    while (a < 360)
    {
        makevectors('0 1 0' * a);
        traceline(bo, bo + v_forward * 900, TRUE, world);
        if (trace_fraction > best)
        {
            best = trace_fraction;
            sigf_arena_yaw = a;
        }
        a = a + 15;
    }
    sigf_arena_ok = TRUE;
};

// set the player down in the arena, looking across it
void() sigf_to_arena =
{
    if (!sigf_arena_ok)
    {
        sigf_pick_arena(self.origin);
        if (!sigf_arena_ok)
            return;
    }
    WriteByte(MSG_BROADCAST, SVC_TEMPENTITY);
    WriteByte(MSG_BROADCAST, TE_TELEPORT);
    WriteCoord(MSG_BROADCAST, self.origin_x);
    WriteCoord(MSG_BROADCAST, self.origin_y);
    WriteCoord(MSG_BROADCAST, self.origin_z);
    setorigin(self, sigf_arena + '0 0 26');
    self.velocity = '0 0 0';
    self.v_angle_y = sigf_arena_yaw + crandom() * 25;
    self.angles_y = self.v_angle_y;
    self.fixangle = TRUE;
};

// a tumbleweed rolls across the arena
void() sigf_tumble_think =
{
    self.nextthink = time + 0.1;
    if (time > self.attack_finished)
        remove(self);
};

void() sigf_tumbleweed =
{
    local entity t;
    makevectors('0 1 0' * self.v_angle_y);
    t = spawn();
    t.classname = "sigf_tumble";
    t.movetype = MOVETYPE_BOUNCE;
    t.solid = SOLID_NOT;
    setmodel(t, "progs/sigf_tumble.spr");
    setorigin(t, self.origin + v_forward * (140 + random() * 160) - v_right * 320 + '0 0 20');
    t.velocity = v_right * (260 + random() * 80) + '0 0 60';
    t.attack_finished = time + 6;
    t.think = sigf_tumble_think;
    t.nextthink = time + 0.1;
};

// the wanted poster nailed up in front of the player
void(float fwd, float side) sigf_poster =
{
    local entity w;
    if (!sigf_find_spot(fwd, side))
        return;
    w = spawn();
    w.classname = "sigf_poster";
    w.movetype = MOVETYPE_NONE;
    w.solid = SOLID_NOT;
    setmodel(w, "progs/sigf_wanted.spr");
    setorigin(w, sigf_spot + '0 0 2');
};

// ---------- scenery: TNT crates that blow up, cacti that block the way ----------
void() sigf_tnt_boom =
{
    self.takedamage = DAMAGE_NO;
    self.classname = "explo_box";
    T_RadiusDamage(self, self, 200, world);
    sound(self, CHAN_VOICE, "weapons/r_exp3.wav", 1, ATTN_NORM);
    particle(self.origin, '0 0 0', 75, 70);
    particle(self.origin, '0 0 140', 232, 70);
    self.origin_z = self.origin_z + 24;
    BecomeExplosion();
};

void() sigf_spawn_tnt =
{
    local float oldz;
    precache_model("progs/sigf_tnt.mdl");
    precache_sound("weapons/r_exp3.wav");
    self.solid = SOLID_BBOX;
    self.movetype = MOVETYPE_NONE;
    setmodel(self, "progs/sigf_tnt.mdl");
    setsize(self, '-16 -16 -24', '16 16 8');
    self.health = 20;
    self.th_die = sigf_tnt_boom;
    self.takedamage = DAMAGE_AIM;
    self.origin_z = self.origin_z + 26;
    oldz = self.origin_z;
    droptofloor();
    if ((oldz - self.origin_z) > 250)
        remove(self);
};

void() sigf_spawn_saloon =
{
    precache_model("progs/sigf_saloon.mdl");
    self.solid = SOLID_BBOX;
    self.movetype = MOVETYPE_NONE;
    setmodel(self, "progs/sigf_saloon.mdl");
    setsize(self, '-44 -44 -24', '44 44 90');
    self.origin_z = self.origin_z + 26;
    droptofloor();
};

void() sigf_spawn_cactus =
{
    precache_model("progs/sigf_cactus.mdl");
    self.solid = SOLID_BBOX;
    self.movetype = MOVETYPE_NONE;
    setmodel(self, "progs/sigf_cactus.mdl");
    setsize(self, '-8 -8 -24', '8 8 48');
    self.origin_z = self.origin_z + 26;
    droptofloor();
};

// a prop standing on the floor at a spot
void(string cls, vector spot) sigf_prop =
{
    local entity e, oself;
    e = spawn();
    e.classname = cls;
    setorigin(e, spot);
    oself = self;
    self = e;
    if (cls == "sigf_tnt")
        sigf_spawn_tnt();
    else if (cls == "sigf_saloon")
    {
        e.angles_y = self.v_angle_y + 180;     // the front door faces the player
        sigf_spawn_saloon();
    }
    else
        sigf_spawn_cactus();
    self = oself;
};

// a prop standing in front of the player: forward, right
void(string cls, float fwd, float side) sigf_scene =
{
    if (!sigf_find_spot(fwd, side))
        return;
    sigf_prop(cls, sigf_spot);
};

// TNT crates around a monster: a dynamite stick near it sets them off
void(entity m) sigf_tnt_ring =
{
    local vector o;
    if (!m)
        return;
    o = m.origin;
    o_z = o_z - 4;
    makevectors(m.angles);
    traceline(o, o + v_right * 70, TRUE, m);
    if (trace_fraction == 1)
        sigf_prop("sigf_tnt", o + v_right * 70);
    traceline(o, o - v_right * 70, TRUE, m);
    if (trace_fraction == 1)
        sigf_prop("sigf_tnt", o - v_right * 70);
};

// ---------- the three hooks ----------
void() SIGF_Precache =
{
    precache_model("progs/v_sigf_revolver.mdl");
    precache_model("progs/sigf_cash.spr");
    precache_model("progs/sigf_tnt.mdl");
    precache_model("progs/sigf_cactus.mdl");
    precache_model("progs/sigf_saloon.mdl");
    precache_model("progs/sigf_tumble.spr");
    precache_sound("weapons/r_exp3.wav");
    precache_sound("sigf/theme.wav");
    precache_model("progs/sigf_wanted.spr");
    precache_model("progs/sigf_mark.spr");
    precache_model("progs/sigf_dynamite.mdl");
    precache_sound("sigf/cash.wav");
    precache_sound("sigf/deadeye.wav");
    precache_sound("sigf/twang.wav");
    SIGF_Preload("monster_sigf_outlaw", monster_sigf_outlaw);
    SIGF_Preload("monster_sigf_horse", monster_sigf_horse);
};

void(float wave) SIGF_DemoWave =
{
    local entity m;
    sigf_to_arena();
    if (wave == 0)
    {
        // the gang rides in: Dead Eye is charged so the first seconds show it
        self.items = self.items | IT_SHOTGUN | IT_SUPER_SHOTGUN | IT_GRENADE_LAUNCHER | IT_NAILGUN;
        self.weapon = IT_SHOTGUN;
        self.ammo_shells = 60;
        self.ammo_rockets = 30;
        W_SetCurrentAmmo();
        self.sigf_eye = 100;
        sigf_scene("sigf_saloon", 520, 0);
        sigf_poster(230, 70);
        sigf_poster(260, -120);
        sigf_poster(330, 190);
        sigf_scene("sigf_cactus", 240, -170);
        sigf_scene("sigf_cactus", 300, 180);
        sigf_scene("sigf_cactus", 380, -60);
        sigf_scene("sigf_cactus", 200, 240);
        sigf_scene("sigf_cactus", 420, 120);
        sigf_mob("monster_sigf_outlaw", monster_sigf_outlaw, 170, -90);
        sigf_mob("monster_sigf_outlaw", monster_sigf_outlaw, 197, 0);
        sigf_mob("monster_sigf_outlaw", monster_sigf_outlaw, 170, 90);
        return;
    }
    if (wave == 1 || wave == 5)
    {
        // dynamite on a horse standing among TNT crates
        self.weapon = IT_GRENADE_LAUNCHER;
        W_SetCurrentAmmo();
        m = sigf_mob("monster_sigf_horse", monster_sigf_horse, 176, 0);
        sigf_tnt_ring(m);
        sigf_mob("monster_sigf_outlaw", monster_sigf_outlaw, 204, 110);
        return;
    }
    if (wave == 3 || wave == 7)
    {
        self.sigf_eye = 100;                // Dead Eye again
        self.weapon = IT_SHOTGUN;
        W_SetCurrentAmmo();
        sigf_mob("monster_sigf_outlaw", monster_sigf_outlaw, 170, -100);
        sigf_mob("monster_sigf_outlaw", monster_sigf_outlaw, 190, 0);
        sigf_mob("monster_sigf_outlaw", monster_sigf_outlaw, 170, 100);
        return;
    }
    // revolver fight against a horse that charges
    self.weapon = IT_SHOTGUN;
    W_SetCurrentAmmo();
    sigf_mob("monster_sigf_outlaw", monster_sigf_outlaw, 176, -60);
    sigf_mob("monster_sigf_horse", monster_sigf_horse, 204, 60);
};

void(entity targ, entity attacker) SIGF_OnKilled =
{
    local float amount;
    if (targ.flags & FL_MONSTER)
    {
        amount = 50;
        if (targ.classname == "monster_sigf_horse")
            amount = 75;
        else if (targ.max_health > 100)
            amount = 150;
        sigf_drop_cash(targ.origin, amount);
        if (attacker.classname == "player" && attacker.sigf_de_state == 0)
        {
            attacker.sigf_eye = attacker.sigf_eye + 34;
            if (attacker.sigf_eye > 100)
                attacker.sigf_eye = 100;
        }
    }
};
