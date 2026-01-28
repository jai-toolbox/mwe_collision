#import "model_loading";
#import "geometry";
#import "opengl";
#import "camera";
#import "movement";
#import "collision";
#import "math";

#import "Basic";
#import "GL";
#import "Random";
#import "Math";
#import "Window_Creation";

Simp  :: #import "Simp";
Input :: #import "Input";

window_width  : s32 = 500;
window_height : s32 = 500;

my_window: Window_Type;

convert_obj_to_indexed_meshes :: (obj_data: *Obj_Data) -> [..] Indexed_Mesh {
    meshes: [..] Indexed_Mesh;
    
    for *obj_object : obj_data.all_objects {
        mesh: Indexed_Mesh;
        current_index: u32 = 0;
        
        for *face : obj_object.faces {
            if face.face_vertices.count < 3 continue;

            // now there are at least 3 vertices on this face.
            
            first_index := current_index;
            
            for *fv : face.face_vertices {
                array_add(*mesh.positions, obj_data.all_positions[fv.position_index]);
                
                // handle optional texture coordinates
                if fv.texture_coordinate_index >= 0 {
                    array_add(*mesh.texture_coordinates, obj_data.all_texture_coordinates[fv.texture_coordinate_index]);
                } else {
                    array_add(*mesh.texture_coordinates, .{0, 0});
                }
                
                // Handle optional normals
                if fv.normal_index >= 0 {
                    array_add(*mesh.normals, obj_data.all_normals[fv.normal_index]);
                } else {
                    array_add(*mesh.normals, .{0, 1, 0});  // default up normal
                }

                // this is temporary
                r1 := random_get_zero_to_one();
                r2 := random_get_zero_to_one();
                r3 := random_get_zero_to_one();
                random_color := Vector3.{r1, r2, r3};

                array_add(*mesh.rgb_colors, random_color);

                current_index += 1;
            }
            
            // fan triangulation (in case there are more than 3 verts on a face)
            for i : 1..face.face_vertices.count-2 {
                array_add(*mesh.indices, first_index);
                array_add(*mesh.indices, first_index + cast(u32) i);
                array_add(*mesh.indices, first_index + cast(u32) i + 1);
            }
        }
        
        array_add(*meshes, mesh);
    }
    
    return meshes;
}

Renderable :: struct {
    indexed_mesh : Indexed_Mesh;
    local_to_world_indices : [..] u32;
    render_object_index : u32;
};


is_key_down :: inline (key : Input.Key_Code) -> bool #must {
	return (Input.input_button_states[cast (s64) key] & .DOWN) != 0;
}

Character :: struct {
    using #as cg : Collision_Geometry;
    using r : Renderable;
}

Movement_Mode :: enum {
    GOD;
    FPS;
}

main :: () {
    obj_data := load_obj("data/basic_map.obj");
    // just assuming that meshes live till the end of the program for now.
    meshes := convert_obj_to_indexed_meshes(*obj_data);

    map : [..] Collision_Geometry;

    movement_mode := Movement_Mode.FPS;


    for meshes {
        cg : Collision_Geometry;
        cg.indexed_triangle_positions.indices = it.indices;
        cg.indexed_triangle_positions.positions = it.positions;

        cg.aabb = create_aabb_from_positions(cg.indexed_triangle_positions.positions);

        array_add(*map, cg);
    }


    my_window = create_window(window_width, window_height, "mwe_model_loading");
    Simp.set_render_target(my_window);
    toggle_fullscreen(my_window, true, null);

    shader_program_handle, success := create_shader_program(VERTEX_SHADER_WITH_CAMERA_AND_PER_OBJECT_TRANSFORMS, VERTEX_COLOR_FRAGMENT_SHADER);
	if !success
        log("shader compilation failed");
		// return false;
    if success 
        log("shader compilation succeeded");


    per_object_transform_renderer : Per_Object_Transform_Renderer;
    per_object_transform_renderer.shader_program_gl_handle = shader_program_handle;
    init(*per_object_transform_renderer);


    character : Character;
    character.indexed_triangle_positions = generate_box(ZERO3, 0.4, 1.75, 0.4); 
    character.aabb = create_aabb_from_positions(character.indexed_triangle_positions.positions);
    character.indexed_mesh.indices = character.indexed_triangle_positions.indices;
    character.indexed_mesh.positions = character.indexed_triangle_positions.positions;

    for 1..character.indexed_mesh.positions.count array_add(*character.indexed_mesh.rgb_colors, .{0, .5, .5});
    for 1..character.indexed_mesh.positions.count array_add(*character.local_to_world_indices, xx 0);

    character.render_object_index = buffer_object(*per_object_transform_renderer, character.indexed_mesh.indices, character.local_to_world_indices, character.indexed_mesh.positions, character.indexed_mesh.rgb_colors);


    camera : Camera;
    camera.position = Y3 * 30;
    velocity : Vector3;
    on_ground : bool;

    renderables : [..] Renderable;
    
    count := 10;
    for meshes {
        renderable: Renderable;
        renderable.indexed_mesh = it;
        
        for 1..renderable.indexed_mesh.positions.count array_add(*renderable.local_to_world_indices, xx count);

        renderable.render_object_index = buffer_object(*per_object_transform_renderer, renderable.indexed_mesh.indices, renderable.local_to_world_indices, renderable.indexed_mesh.positions, renderable.indexed_mesh.rgb_colors);

        array_add(*renderables, renderable);

        count += 1;
    }

	delta_time := 0.01667;
    quit := false;
    while !quit {

        frame_start := current_time_monotonic ();

        Input.update_window_events();
        for Input.events_this_frame {
            if it.type == .QUIT then quit = true;

            if it.type == {
              case .KEYBOARD;
                if it.key_pressed && it.key_code == .ESCAPE {
                    quit = true;
                }
            }
        }

    
        for Input.get_window_resizes() {
            Simp.update_window(it.window);  
            if it.window == my_window {
                should_reinit := (it.width != window_width) || (it.height != window_height);

                window_width  = it.width;
                window_height = it.height;
            }
        }
    
        

        x, y, success := get_mouse_pointer_position(my_window, false); 

        update_angles(*camera, x, y);

        vx, vy, vw, vh := get_dimensions (my_window, false);
        // log("using: % %", vw, vh);
        // update_matrices(*camera, vw, vh);
        update_matrices_third_person(*camera, vw, vh);
        per_object_transform_renderer.local_to_world_matrices[0] = make_translation_matrix4(camera.position);

        // this is the character.
        queue_render(*per_object_transform_renderer, character.render_object_index);

        for renderables queue_render(*per_object_transform_renderer, it.render_object_index);

        row_major := GL_TRUE;
        num_matrices_we_are_updating :u32 = 1;

        if (movement_mode == .GOD) {
            gmi := God_Mode_Input.{
                is_key_down (xx #char "E"),
                is_key_down (xx #char "Q"),
                is_key_down (xx #char "W"),
                is_key_down (xx #char "S"),
                is_key_down (xx #char "D"),
                is_key_down (xx #char "A"),
                is_key_down (xx #char "V"),
                is_key_down (Input.Key_Code.SHIFT),
            }; 


            velocity = get_new_god_mode_velocity(velocity, get_forward(*camera), gmi, delta_time);
        } 
        if (movement_mode == .FPS) {
            fpmi := First_Person_Movement_Input.{
                is_key_down (xx #char "W"),
                is_key_down (xx #char "S"),
                is_key_down (xx #char "D"),
                is_key_down (xx #char "A"),
                is_key_down (xx #char "V"),
            }; 

            ground_state : Ground_State = ifx on_ground then .ON_GROUND else .IN_AIR;

            velocity = get_new_first_person_velocity(velocity, fpmi, get_forward(*camera), delta_time, ground_state, Movement_Params.{});
        }

        camera.position += velocity * delta_time;

        resolve_collisions_against_body(map, character, *camera.position, *velocity, *on_ground);

        glUseProgram(per_object_transform_renderer.shader_program_gl_handle);

        glUniformMatrix4fv(glGetUniformLocation(per_object_transform_renderer.shader_program_gl_handle, "world_to_camera"), num_matrices_we_are_updating, row_major, *camera.world_to_camera.coef[0][0]);
        glUniformMatrix4fv(glGetUniformLocation(per_object_transform_renderer.shader_program_gl_handle, "camera_to_clip"), num_matrices_we_are_updating, row_major, *camera.camera_to_clip.coef[0][0]);

		Simp.update_window (my_window);
        Simp.clear_render_target(.15, .08, .08, 1);

		glDepthMask (GL_TRUE);
		glEnable (GL_DEPTH_TEST);

		glClear (GL_DEPTH_BUFFER_BIT);

        render(*per_object_transform_renderer);

        Simp.swap_buffers(my_window);


		frame_end := current_time_monotonic ();
		delta_time = cast (float) to_float64_seconds (frame_end - frame_start);

    }



}
