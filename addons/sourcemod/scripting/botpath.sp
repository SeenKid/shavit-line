#pragma semicolon 1
#pragma newdecls required

#include <clientprefs>
#include <closestpos>
#include <sdktools>
#include <shavit>

#include <sdkhooks>
#include <sourcemod>
#include <smjansson>
#include <ripext>
#include <shavit/replay-file>
#include <shavit/replay-playback>
#include <shavit/replay-recorder>

int sprite;

ArrayList ReplayFrames[TRACKS_SIZE][STYLE_LIMIT];
ClosestPos hClosestPos[TRACKS_SIZE][STYLE_LIMIT];
Cookie lines_settings;

int cTrack[66];
int cStyle[66];
int ticks[66];
bool drawLines[66];

public Plugin myinfo = {
	name = "shavit-line",
	author = "SeenKid",
	description = "Shows the WR route with a path on the ground. Use the command sm_line to toggle.",
	version = "1.0.2",
	url = "https://github.com/SeenKid/shavit-line"
};

public void OnPluginStart() {
	lines_settings = new Cookie( "shavit_lines", "", CookieAccess_Private );
	
	Shavit_OnReplaysLoaded();
	for( int z = 1; z <= MaxClients; z++ ) {
		if( IsClientInGame(z) && !IsFakeClient(z) ) {
			cStyle[z] = Shavit_GetBhopStyle(z);
			cTrack[z] = Shavit_GetClientTrack(z);
			
			if( AreClientCookiesCached(z) ) {
				OnClientCookiesCached(z);
			}
		}
	}
	RegConsoleCmd( "sm_line", line_callback );
}

Action line_callback(int client, int args) {
	drawLines[client] = !drawLines[client];
	// Please, do not remove copyright message.
	ReplyToCommand(client, "｢ Shavit-Line ｣ Plugin made by SeenKid");
	char buffer[2];
	buffer[0] = view_as<char>(drawLines[client]) + '0';
	lines_settings.Set(client, buffer);
	return Plugin_Handled;
}

public void OnClientCookiesCached(int client) {
	if( !IsFakeClient(client) ) {
		char szCookie[4];
		lines_settings.Get(client, szCookie, sizeof szCookie );
		if( !szCookie[0] ) {
			szCookie[0] = '1';
		}
		drawLines[client] = szCookie[0] == '1';
	}
}

public void OnConfigsExecuted() {
	sprite = PrecacheModel("sprites/laserbeam.vmt");
}

public void Shavit_OnReplaysLoaded() {
	for( int z; z < TRACKS_SIZE; z++ ) {
		for( int v; v < STYLE_LIMIT; v++ ) {		
			delete hClosestPos[z][v];
			delete ReplayFrames[z][v];		
			if( (ReplayFrames[z][v] = Shavit_GetReplayFrames(v, z)) ) {
				hClosestPos[z][v] = new ClosestPos(ReplayFrames[z][v], 0, 0, Shavit_GetReplayFrameCount(v,z));	
			}
		}
	}
}

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual) {
	cTrack[client] = track;
	cStyle[client] = newstyle;
}

public void Shavit_OnReplaySaved(int client, int style, float time, int jumps, int strafes, float sync, int track, 
									float oldtime, float perfs, float avgvel, float maxvel, int timestamp, bool isbestreplay, 
									bool istoolong, bool iscopy, const char[] replaypath, ArrayList frames, int preframes, int postframes, const char[] name) {
	delete hClosestPos[track][style];
	delete ReplayFrames[track][style];

	ReplayFrames[track][style] = frames.Clone();
	hClosestPos[track][style] = new ClosestPos(ReplayFrames[track][style], 0, 0, frames.Length);	
}

#define TE_TIME 1.0
#define TE_MIN 0.5
#define TE_MAX 0.5

int boxcolor[2][4] = { {255,255,255,255}, {128,0,128,255} };
public Action OnPlayerRunCmd(int client) {
	if( IsFakeClient(client) || !drawLines[client]) {
		return Plugin_Continue;
	}

	if( (++ticks[client] % 60) == 0 ) {
		ticks[client] = 0;

		int style = cStyle[client];
		int track = cTrack[client];
		ArrayList list = ReplayFrames[track][style];
		if( !list ) {
			return Plugin_Continue;	
		}
	
		float pos[3];
		GetClientAbsOrigin(client, pos);
	
		int closeframe = max(0,hClosestPos[track][style].Find(pos) - 2500);
		int endframe = min(list.Length, closeframe + 2500);
	
		bool draw;
		int flags;
	
		frame_t aFrame;
		for( ; closeframe < endframe; closeframe++ ) {
			list.GetArray(closeframe, aFrame, 8);
	
			if( aFrame.flags & FL_ONGROUND && !(flags & FL_ONGROUND) ) {
				aFrame.pos[2] += 2.5;
	
				DrawBox(client, aFrame.pos, boxcolor[(flags & FL_DUCKING) ? 0:1]);
	
				if( draw ) {
					DrawBeam(client, pos, aFrame.pos, TE_TIME, TE_MIN, TE_MAX, { 0, 0, 255, 255}, 0.0, 0);
				}
	
				if(!draw) {
					draw = true;
				}
				pos = aFrame.pos;
			}
	
			flags = aFrame.flags;
		}
	}

	return Plugin_Continue;	
}

float box_offset[4][2] = {
	{-10.0, 10.0},  
	{10.0, 10.0},   
	{-10.0, -10.0}, 
	{10.0, -10.0},  
};

void DrawBox(int client, float pos[3], int color[4] ) {
	float square[4][3];
	for (int z = 0; z < 4; z++) {
		square[z][0] = pos[0] + box_offset[z][0];
		square[z][1] = pos[1] + box_offset[z][1];
		square[z][2] = pos[2];
	}
	DrawBeam(client, square[0], square[1], TE_TIME, TE_MIN, TE_MAX, color, 0.0, 0);
	DrawBeam(client, square[0], square[2], TE_TIME, TE_MIN, TE_MAX, color, 0.0, 0);
	DrawBeam(client, square[2], square[3], TE_TIME, TE_MIN, TE_MAX, color, 0.0, 0);
	DrawBeam(client, square[1], square[3], TE_TIME, TE_MIN, TE_MAX, color, 0.0, 0);
}

void DrawBeam(int client, float startvec[3], float endvec[3], float life, float width, float endwidth, int color[4], float amplitude, int speed) {
	TE_SetupBeamPoints(startvec, endvec, sprite, 0, 0, 66, life, width, endwidth, 0, amplitude, color, speed);
	TE_SendToClient(client);
}

int min(int a, int b) {
    return a < b ? a : b;
}

int max(int a, int b) {
    return a > b ? a : b;
}
